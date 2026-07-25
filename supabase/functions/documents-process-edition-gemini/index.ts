// EXPERIMENT, not production: same async multi-page shape as
// documents-process-edition, but OCR is Gemini 3.6 Flash reading each page
// directly (top+bottom half crops via pdf-lib CropBox, no Sarvam call) —
// built to compare against the Sarvam-based pipeline on the same real PDF
// before deciding whether to switch. TTS reuses documents-synthesize
// unmodified (already gemini-2.5-flash-preview-tts).
//
// Produces a newspapers row titled "<original> [Gemini3.6 Test]" so it sits
// alongside the Sarvam-ingested edition of the same file for side-by-side
// comparison in the app, instead of overwriting it.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument } from "npm:pdf-lib@1.17.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-subscription-tier",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const MAX_PAGES = 24;
// gemini-3.6-flash was tried first (per the original ask) but is unreliable
// for this: isolated testing (documents-holistic-test) showed it burning its
// entire thinking budget (1701 tokens) on page 1 of this exact edition and
// returning ZERO output tokens — no error, no safety block, just silence.
// gemini-2.5-flash handled the identical raw PDF bytes cleanly. Falling back
// to it rather than building around a model that fails unpredictably on real
// content.
const MODEL = "gemini-3.5-flash";
const MODEL_SUPPORTS_THINKING_OFF = /^gemini-(2\.5|3\.5)-/.test(MODEL);

function jwtRole(req: Request): string {
  try {
    const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    return payload.role ?? "";
  } catch {
    return "";
  }
}

function parseDateFromFilename(name: string): string {
  const m = name.match(/(20\d{2})(\d{2})(\d{2})/);
  if (!m) return "";
  const [, y, mo, d] = m;
  if (+mo < 1 || +mo > 12 || +d < 1 || +d > 31) return "";
  return `${y}-${mo}-${d}`;
}

function todayIST(): string {
  return new Date(Date.now() + 5.5 * 3600_000).toISOString().split("T")[0];
}

function bytesToBase64(bytes: Uint8Array): string {
  const CHUNK = 8192;
  let binary = "";
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, Math.min(i + CHUNK, bytes.length)));
  }
  return btoa(binary);
}

async function normalizeToPdf(bytes: Uint8Array): Promise<Uint8Array> {
  const isJpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPng = bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  if (!isJpeg && !isPng) return bytes;
  const doc = await PDFDocument.create();
  const img = isJpeg ? await doc.embedJpg(bytes) : await doc.embedPng(bytes);
  const page = doc.addPage([img.width, img.height]);
  page.drawImage(img, { x: 0, y: 0, width: img.width, height: img.height });
  return await doc.save();
}

function estimateDurationSeconds(text: string): number {
  return Math.max(15, Math.round((text.length / 700) * 60));
}

// ── Gemini holistic page-half read ──────────────────────────────────────────

interface HolisticArticle {
  title: string;
  category: string;
  body: string;
  continuation: string | null;
}

const PROMPT = `This is a full page of a Telugu newspaper. Read it directly and extract
EVERY distinct news item visible on the page — do not skip small items,
kickers, or briefs.

For each item, return:
- "title": the headline, in the original Telugu (or English if the headline
  itself is in English).
- "category": one of International, National, State, District, Politics,
  Editorial, Opinion, Business, Sports, Entertainment, Health, Sci-Tech,
  Education, Agriculture, Crime, Judiciary, Devotional, Trending, News
- "body": the full visible body text, verbatim, in reading order, including
  any literal continuation marker text printed on the page (e.g. "మిగతా 3వ
  పేజీలో", "సశేషం", ">7", "మొదటిపేజీ తరువాయి") exactly as it appears — do not
  paraphrase or drop these, they are load-bearing for later processing.
- "continuation": null, or a short note if the page text itself says it
  continues elsewhere.

Do NOT merge two unrelated items under one title. Do NOT invent a title for
one item by borrowing text from a different, unrelated item.

Also return "printedPageNumber": the page number printed on the page itself
(masthead/footer), as an integer, or null if not visible.

Return ONLY this JSON:
{"printedPageNumber": null, "articles": [{"title": "", "category": "", "body": "", "continuation": null}]}`;

async function callHolistic(
  pdfHalfBytes: Uint8Array,
  geminiKey: string,
): Promise<{ printedPageNumber: number | null; articles: HolisticArticle[] }> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${geminiKey}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{
        role: "user",
        parts: [
          { inline_data: { mime_type: "application/pdf", data: bytesToBase64(pdfHalfBytes) } },
          { text: PROMPT },
        ],
      }],
      generationConfig: {
        maxOutputTokens: 32000,
        responseMimeType: "application/json",
        ...(MODEL_SUPPORTS_THINKING_OFF ? { thinkingConfig: { thinkingBudget: 0 } } : {}),
      },
      // Default safety thresholds false-positived on legitimate protest/
      // police-crackdown news coverage (finishReason=PROHIBITED_CONTENT on a
      // page discussing student protests and arrests) — this is a
      // transcription task over real newspaper content, not generation.
      safetySettings: [
        { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_ONLY_HIGH" },
        { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_ONLY_HIGH" },
        { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_ONLY_HIGH" },
        { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_ONLY_HIGH" },
      ],
    }),
    signal: AbortSignal.timeout(140_000),
  });
  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Gemini holistic HTTP ${resp.status}: ${errText.slice(0, 200)}`);
  }
  const data = await resp.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> }; finishReason?: string }>;
    promptFeedback?: { blockReason?: string };
  };
  const text = (data.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? "").join("");
  if (!text.trim()) {
    const finishReason = data.candidates?.[0]?.finishReason ?? "unknown";
    const blockReason = data.promptFeedback?.blockReason ?? "";
    throw new Error(`Gemini holistic: empty response (finishReason=${finishReason}${blockReason ? `, blockReason=${blockReason}` : ""})`);
  }
  const match = text.match(/\{[\s\S]*\}/);
  const parsed = JSON.parse(match ? match[0] : text) as {
    printedPageNumber?: number | null;
    articles?: HolisticArticle[];
  };
  return { printedPageNumber: parsed.printedPageNumber ?? null, articles: parsed.articles ?? [] };
}

// ── Page continuation (duplicated from documents-process-edition on purpose —
// this is a throwaway comparison branch, not meant to share code with prod) ──

const CONT_TO =
  /(?:(?:మిగతా|సశేషం|తరువాయి)\s*\(?\s*(?<page1>\d{1,2})\s*(?:వ\s*)?(?:పేజీలో|పేజీ|లో)[^)]*\)?)|(?:>\s*(?<page2>\d{1,2})\s*(?:వ\s*పేజీలో)?)/;
const CONT_FROM = /(?:\d{1,2}\s*(?:వ\s*)?పేజీ|మొదటి\s*పేజీ)\s*తరువాయి/;

function titleOverlapMatch(t1: string, t2: string): boolean {
  const n1 = (t1 ?? "").trim().replace(/\s+/g, " ");
  const n2 = (t2 ?? "").trim().replace(/\s+/g, " ");
  if (!n1 || !n2) return false;
  const [shorter, longer] = n1.length <= n2.length ? [n1, n2] : [n2, n1];
  if (shorter.length < 10) return false;
  return longer.includes(shorter);
}

// deno-lint-ignore no-explicit-any
async function finalizeContinuations(supabase: any, newspaperId: string): Promise<void> {
  if (!newspaperId) return;
  const { data: arts } = await supabase.from("articles")
    .select("id,title,full_content,content_preview,page_number")
    .eq("newspaper_id", newspaperId)
    .order("page_number");
  if (!arts || arts.length < 2) return;

  for (const a of arts) {
    const body: string = a.full_content ?? "";
    const m = body.match(CONT_TO);
    if (!m) continue;
    const targetPage = parseInt(m.groups?.page1 ?? m.groups?.page2 ?? "", 10);
    if (Number.isNaN(targetPage)) continue;

    const cands = arts.filter((x: typeof a) =>
      x.page_number === targetPage && x.id !== a.id && x.full_content);
    let best: typeof a | null = null;
    let bestScore = 0;
    for (const c of cands) {
      const head = (c.full_content as string).slice(0, 90);
      let score = 0;
      if (CONT_FROM.test(head)) score += 2;
      if (titleOverlapMatch(a.title as string, c.title as string)) score += 2;
      if (score > bestScore) { bestScore = score; best = c; }
    }

    const head = body.replace(CONT_TO, " ").replace(/\s{2,}/g, " ").trim();
    if (best && bestScore >= 2) {
      const contBody = (best.full_content as string)
        .replace(CONT_FROM, " ")
        .replace(/^[\s\S]{0,40}?తరువాయి[^)]*\)?/, " ")
        .replace(/\s{2,}/g, " ")
        .trim();
      const merged = `${head} ${contBody}`.trim();
      await supabase.from("articles")
        .update({ full_content: merged, content_preview: merged.slice(0, 200) })
        .eq("id", a.id);
      await supabase.from("articles").delete().eq("id", best.id);
    } else if (head !== body) {
      await supabase.from("articles")
        .update({ full_content: head, content_preview: head.slice(0, 200) })
        .eq("id", a.id);
    }
  }
}

// ── Per-page processing ──────────────────────────────────────────────────────

// deno-lint-ignore no-explicit-any
async function processPage(supabase: any, jobId: string, page: number, geminiKey: string): Promise<void> {
  const { data: job } = await supabase.from("processing_jobs").select("*").eq("id", jobId).single();
  if (!job || job.status === "failed") return;

  const sourcePath = job.source_path ?? `editions/${jobId}.pdf`;
  try {
    const { data: blob, error: dlErr } = await supabase.storage.from("uploads").download(sourcePath);
    if (dlErr) throw new Error(`pdf download: ${dlErr.message}`);
    const srcBytes = await normalizeToPdf(new Uint8Array(await blob.arrayBuffer()));
    const src = await PDFDocument.load(srcBytes);

    // Whole page, uncropped — every earlier successful gemini-3.6-flash test
    // this session used a rasterized JPEG; CropBox-cropped halves of the
    // native source PDF instead produced empty responses (PROHIBITED_CONTENT,
    // then OTHER) on this same page. This isolates whether raw-PDF ingestion
    // itself works for 3.6-flash before layering the half-split back in.
    const single = await PDFDocument.create();
    const [pg] = await single.copyPages(src, [page - 1]);
    single.addPage(pg);
    const pageBytes = await single.save();

    const result = await callHolistic(pageBytes, geminiKey);
    const printedPage = result.printedPageNumber ?? page;
    const combined = result.articles.filter((a) => (a.body ?? "").trim().length > 0);

    const rows = combined.map((a, i) => ({
      newspaper_id: job.newspaper_id,
      title: a.title || "(untitled)",
      content_preview: (a.body ?? "").replace(/\n/g, " ").slice(0, 200),
      full_content: a.body ?? "",
      section: a.category || "News",
      page_number: printedPage,
      processing_status: "ready",
      quality_score: 0.85,
      position_json: {
        article_index: i + 1,
        page: printedPage,
        pdf_page: page,
        estimated_duration_seconds: estimateDurationSeconds(a.body ?? ""),
        extraction_engine: "gemini-3.6-holistic-fullpage",
      },
    }));
    if (rows.length) {
      const { error: insErr } = await supabase.from("articles").insert(rows);
      if (insErr) throw new Error(`articles insert: ${insErr.message}`);
    }

    const totalArticles = (job.article_count ?? 0) + rows.length;
    const isLastPage = page >= job.total_pages;
    await supabase.from("processing_jobs").update({
      done_pages: page,
      article_count: totalArticles,
      status: isLastPage ? (totalArticles > 0 ? "completed" : "failed") : "processing",
      ...(isLastPage && totalArticles === 0
        ? { error: "Gemini completed on every page but no articles were extracted." }
        : {}),
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);
    console.log(`[edition-gemini] job ${jobId} page ${page}/${job.total_pages}: ${rows.length} articles`);
  } catch (e) {
    const msg = (e as Error).message;
    console.warn(`[edition-gemini] page ${page} failed: ${msg}`);
    const totalArticles = job.article_count ?? 0;
    const isLastPage = page >= job.total_pages;
    await supabase.from("processing_jobs").update({
      done_pages: page,
      failed_pages: [...(job.failed_pages ?? []), { page, error: msg.slice(0, 200) }],
      status: isLastPage ? (totalArticles > 0 ? "completed" : "failed") : "processing",
      ...(isLastPage && totalArticles === 0
        ? { error: `All pages failed; last error: ${msg.slice(0, 200)}` }
        : {}),
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);
  }

  if (page < job.total_pages) {
    fireContinuation(jobId, page + 1, geminiKey);
  } else {
    await finalizeContinuations(supabase, job.newspaper_id);
    await supabase.storage.from("uploads").remove([sourcePath]).then(() => {}, () => {});
    console.log(`[edition-gemini] job ${jobId} completed`);
  }
}

function fireContinuation(jobId: string, page: number, geminiKey: string): void {
  const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/documents-process-edition-gemini`;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const internal = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const p = fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${anon}`,
      "apikey": anon,
      "x-internal-token": internal,
    },
    body: JSON.stringify({ job_id: jobId, page, geminiKey }),
  }).then(async (r) => {
    if (!r.ok) console.warn(`[edition-gemini] continuation page ${page} -> HTTP ${r.status}`);
    await r.body?.cancel();
  }).catch((e) => console.warn("[edition-gemini] continuation fire failed:", e.message));
  // deno-lint-ignore no-explicit-any
  (globalThis as any).EdgeRuntime?.waitUntil?.(p);
}

// ── Main ──────────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY");
  if (!SUPABASE_URL || !SERVICE_KEY || !GEMINI_KEY) {
    return json({ error: "config_missing" }, 500);
  }
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
  const contentType = req.headers.get("content-type") ?? "";

  if (contentType.includes("application/json")) {
    const body = await req.json().catch(() => ({})) as { job_id?: string; page?: number; geminiKey?: string };
    if (body.job_id && body.page) {
      const internal = req.headers.get("x-internal-token") ?? "";
      if (internal !== SERVICE_KEY && jwtRole(req) !== "service_role") {
        return json({ error: "forbidden" }, 403);
      }
      await processPage(supabase, body.job_id, body.page, body.geminiKey ?? GEMINI_KEY);
      return json({ ok: true, job_id: body.job_id, page: body.page });
    }
    return json({ error: "bad_request" }, 400);
  }

  try {
    const form = await req.formData();
    const file = form.get("document");
    if (!(file instanceof File)) return json({ error: "missing_file" }, 400);
    if (file.size > 60 * 1024 * 1024) return json({ error: "file_too_large", message: "Max 60 MB." }, 413);

    const originalName = file.name || "edition.pdf";
    const safe = originalName.replace(/[^a-zA-Z0-9._-]/g, "_");
    const sourcePath = `editions/${Date.now()}_${safe}`;
    const bytes = await normalizeToPdf(new Uint8Array(await file.arrayBuffer()));
    const { error: upErr } = await supabase.storage.from("uploads")
      .upload(sourcePath, bytes, { contentType: "application/pdf", upsert: true });
    if (upErr) throw new Error(`pdf store: ${upErr.message}`);

    const pdf = await PDFDocument.load(bytes);
    const totalPages = Math.min(pdf.getPageCount(), MAX_PAGES);
    if (totalPages === 0) return json({ error: "empty_pdf" }, 400);

    const pubDate = parseDateFromFilename(originalName) || todayIST();
    const title = `${originalName.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim()} [${MODEL} Test]`;

    const { data: existing } = await supabase
      .from("newspapers").select("id")
      .eq("title", title).eq("publication_date", pubDate).limit(1).maybeSingle();
    let newspaperId: string;
    if (existing?.id) {
      newspaperId = existing.id;
      await supabase.from("articles").delete().eq("newspaper_id", newspaperId);
    } else {
      const { data: created, error: nErr } = await supabase
        .from("newspapers").insert({ title, publication_date: pubDate, language: "te" })
        .select("id").single();
      if (nErr) throw new Error(`newspaper insert: ${nErr.message}`);
      newspaperId = created.id;
    }

    const { data: jobRow, error: jErr } = await supabase
      .from("processing_jobs")
      .insert({ filename: originalName, status: "processing", total_pages: totalPages, newspaper_id: newspaperId, source_path: sourcePath })
      .select("id").single();
    if (jErr) throw new Error(`job insert: ${jErr.message}`);
    const jobId = jobRow.id as string;

    fireContinuation(jobId, 1, GEMINI_KEY);
    return json({ ok: true, jobId, newspaperId, totalPages, pubDate, title });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-process-edition-gemini]", err);
    return json({ error: "edition_failed", message }, 500);
  }
});
