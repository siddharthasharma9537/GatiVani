// Async multi-page edition processing.
//
// A full Telugu daily (18–24 pages) cannot run synchronously: the per-page
// pipeline (Sarvam OCR ~20s + structure assignment ~20s) times a 20-page
// edition exceeds any single invocation budget. Instead:
//
//   POST multipart {document}  → store PDF, count pages, create processing_jobs
//                                row, fire page-1 continuation, return job_id
//   POST json {job_id, page}   → (internal, service-role only) process ONE page,
//                                update progress, fire next page
//   client polls               → GET rest/v1/processing_jobs?id=eq.{job_id}
//
// Articles from every page aggregate under one newspapers row with correct
// page_number. Page failures are recorded in failed_pages and skipped — a bad
// page never kills the edition.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument } from "npm:pdf-lib@1.17.1";
import { extractArticlesStructured, type UsageCtx } from "../_shared/structure.ts";
import { generate } from "../_shared/gemini.ts";
import { logCall, ocrPaise } from "../_shared/usage.ts";
import { rasterFirstPage } from "../_shared/raster.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-subscription-tier, x-user-gemini-key",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Trial-phase cap: anon users may process a full edition, bounded by the
// 2/hour/IP rate limit below. Tighten with real auth tiers later.
const MAX_PAGES = 24;
const SARVAM_BASE = "https://api.sarvam.ai";

function jwtRole(req: Request): string {
  try {
    const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    return payload.role ?? "";
  } catch {
    return "";
  }
}

// ── Sarvam OCR for one page-PDF (doc-digitization job flow) ──────────────────

async function sarvamPost(path: string, key: string, body: unknown): Promise<Record<string, unknown>> {
  const r = await fetch(`${SARVAM_BASE}${path}`, {
    method: "POST",
    headers: { "api-subscription-key": key, "Content-Type": "application/json" },
    body: JSON.stringify(body ?? {}),
    signal: AbortSignal.timeout(30_000),
  });
  if (!r.ok) throw new Error(`${path} -> HTTP ${r.status}: ${(await r.text()).slice(0, 120)}`);
  return await r.json() as Record<string, unknown>;
}

async function ocrPageToHtml(pageBytes: Uint8Array, sarvamKey: string): Promise<string> {
  const job = await sarvamPost("/doc-digitization/job/v1", sarvamKey, {
    job_parameters: { language: "te-IN", output_format: "html" },
  }) as { job_id: string };

  const up = await sarvamPost("/doc-digitization/job/v1/upload-files", sarvamKey, {
    job_id: job.job_id,
    files: ["page.pdf"],
  }) as { upload_urls: Record<string, { file_url: string; file_metadata?: Record<string, string> }> };
  const info = Object.values(up.upload_urls)[0];
  const headers: Record<string, string> = { "x-ms-blob-type": "BlockBlob" };
  for (const [k, v] of Object.entries(info.file_metadata ?? {})) {
    if (typeof v === "string") headers[k] = v;
  }
  const put = await fetch(info.file_url, { method: "PUT", body: pageBytes as BodyInit, headers });
  if (!put.ok) throw new Error(`OCR upload PUT -> ${put.status}`);

  await sarvamPost(`/doc-digitization/job/v1/${job.job_id}/start`, sarvamKey, {});
  let state = "";
  for (let i = 0; i < 18; i++) {
    await new Promise((r) => setTimeout(r, 5000));
    const st = await fetch(`${SARVAM_BASE}/doc-digitization/job/v1/${job.job_id}/status`, {
      headers: { "api-subscription-key": sarvamKey },
    });
    state = ((await st.json()) as { job_state?: string }).job_state ?? "";
    if (state === "Completed") break;
    if (state === "Failed" || state === "Cancelled") throw new Error(`OCR job ${state}`);
  }
  if (state !== "Completed") throw new Error("OCR job timed out");

  const dl = await sarvamPost(`/doc-digitization/job/v1/${job.job_id}/download-files`, sarvamKey, {}) as {
    download_urls: Record<string, { file_url: string } | string>;
  };
  for (const v of Object.values(dl.download_urls)) {
    const url = typeof v === "string" ? v : v.file_url;
    if (typeof url !== "string" || !url.startsWith("http")) continue;
    const resp = await fetch(url);
    if (!resp.ok) continue;
    const buf = new Uint8Array(await resp.arrayBuffer());
    if (buf[0] === 0x50 && buf[1] === 0x4b) {  // zip
      const { ZipReader, Uint8ArrayReader, TextWriter } =
        await import("https://deno.land/x/zipjs@v2.7.45/index.js");
      const zr = new ZipReader(new Uint8ArrayReader(buf));
      for (const entry of await zr.getEntries()) {
        if (!entry.directory && /\.html?$/i.test(entry.filename)) {
          const html = await entry.getData?.(new TextWriter()) as string;
          await zr.close();
          return html;
        }
      }
      await zr.close();
    } else {
      const text = new TextDecoder().decode(buf);
      if (text.includes("<")) return text;
    }
  }
  throw new Error("no HTML in OCR result");
}

// "Eenadu_TELANGANA_20260512.pdf" → "2026-05-12"
function parseDateFromFilename(name: string): string {
  const m = name.match(/(20\d{2})(\d{2})(\d{2})/);
  if (!m) return "";
  const [, y, mo, d] = m;
  if (+mo < 1 || +mo > 12 || +d < 1 || +d > 31) return "";
  return `${y}-${mo}-${d}`;
}

// Indian newspapers print by IST calendar day, but the edge runtime's wall
// clock is UTC — a plain toISOString() split would misdate anything uploaded
// 00:00-05:30 IST as the previous day. IST is a fixed UTC+5:30, no DST.
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

// The date actually printed on the page (masthead/dateline) is the ground
// truth for "which edition is this" — most uploads (camera photos) have no
// dated filename, and would otherwise all collide on today's date. Cheap
// flash-lite vision call; failures are non-fatal (caller falls back to the
// filename, then today).
async function detectPrintedDate(
  pageBytes: Uint8Array,
  geminiKey: string,
  ctx?: UsageCtx,
): Promise<string> {
  try {
    const prompt = 'If a publication/issue date is printed on this newspaper page ' +
      '(masthead or dateline), return it as YYYY-MM-DD. Otherwise return "". ' +
      'Return ONLY JSON: {"publicationDate":""}';
    const { status, text } = await generate({
      tier: "fast",
      parts: [
        { inline_data: { mime_type: "application/pdf", data: bytesToBase64(pageBytes) } },
        { text: prompt },
      ],
      apiKey: geminiKey,
      maxOutputTokens: 256,
      timeoutMs: 20_000,
      ctx: ctx ? { ...ctx, page: 1 } : undefined,
    });
    if (status !== 200) return "";
    const m = text.match(/"publicationDate"\s*:\s*"(\d{4}-\d{2}-\d{2})"/);
    return m ? m[1] : "";
  } catch (e) {
    console.warn("[edition] printed-date detection failed:", (e as Error).message);
    return "";
  }
}

function estimateDurationSeconds(text: string): number {
  return Math.max(15, Math.round((text.length / 700) * 60));
}

// Wrap a JPEG/PNG into a single-page PDF (page sized to the image). If the bytes
// are already a PDF (or an unrecognized type), return them unchanged.
async function normalizeToPdf(bytes: Uint8Array): Promise<Uint8Array> {
  const isJpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPng = bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47;
  if (!isJpeg && !isPng) return bytes; // already PDF (or let load() error clearly)

  const doc = await PDFDocument.create();
  const img = isJpeg ? await doc.embedJpg(bytes) : await doc.embedPng(bytes);
  const page = doc.addPage([img.width, img.height]);
  page.drawImage(img, { x: 0, y: 0, width: img.width, height: img.height });
  return await doc.save();
}

// ── Page continuation ─────────────────────────────────────────────────────────

// deno-lint-ignore no-explicit-any
async function processPage(
  supabase: any, jobId: string, page: number, geminiKey: string,
): Promise<void> {
  const SARVAM = Deno.env.get("SARVAM_API_KEY")!;
  const GEMINI = geminiKey;

  const { data: job } = await supabase
    .from("processing_jobs").select("*").eq("id", jobId).single();
  if (!job || job.status === "failed") return;

  const sourcePath = job.source_path ?? `editions/${jobId}.pdf`;
  try {
    // load source PDF from storage and cut out this page
    const { data: blob, error: dlErr } = await supabase.storage
      .from("uploads").download(sourcePath);
    if (dlErr) throw new Error(`pdf download: ${dlErr.message}`);
    const srcBytes = await normalizeToPdf(new Uint8Array(await blob.arrayBuffer()));
    const src = await PDFDocument.load(srcBytes);
    const single = await PDFDocument.create();
    const [pg] = await single.copyPages(src, [page - 1]);
    single.addPage(pg);
    const pageBytes = await single.save();

    // Cost ledger context: every Gemini call made below this point is
    // attributed to this job/page/edition. See _shared/usage.ts.
    const usage: UsageCtx = {
      supabase,
      fn: "documents-process-edition",
      jobId,
      newspaperId: job.newspaper_id,
      page,
    };

    const ocrStart = Date.now();
    const html = await ocrPageToHtml(new Uint8Array(pageBytes), SARVAM);
    await logCall(supabase, {
      fn: "documents-process-edition",
      kind: "ocr",
      provider: "sarvam",
      model: "sarvam-doc-digitization-v1",
      jobId,
      newspaperId: job.newspaper_id,
      page,
      pages: 1,
      inrPaise: ocrPaise(1),
      latencyMs: Date.now() - ocrStart,
    });

    // Optionally hand Gemini a downscaled JPEG instead of the raw page PDF —
    // image input is billed by pixel area. Off unless RASTER_PAGES=true, and
    // null on any failure, in which case this is exactly the old behaviour.
    // See _shared/raster.ts for why it ships disabled.
    const raster = await rasterFirstPage(new Uint8Array(pageBytes));
    if (raster) {
      console.log(`[edition] page ${page} rastered ${raster.width}x${raster.height}`);
    }
    const result = await extractArticlesStructured(
      html,
      raster ? raster.bytes : new Uint8Array(pageBytes),
      raster ? raster.mimeType : "application/pdf",
      GEMINI,
      usage,
    );

    const rows = result.articles.map((a, i) => ({
      newspaper_id: job.newspaper_id,
      title: a.title,
      content_preview: a.content.replace(/\n/g, " ").slice(0, 200),
      full_content: a.content,
      section: a.category || "News",
      // Prefer the printed page number (cover/main pages shift the PDF index).
      page_number: result.printedPage ?? page,
      processing_status: a.review.length ? "review" : "ready",
      quality_score: a.review.length ? 0.7 : 0.95,
      position_json: {
        article_index: i + 1,
        page: result.printedPage ?? page,
        pdf_page: page,
        subheadings: a.subheadings,
        captions: a.captions,
        review_flags: a.review.length ? a.review : undefined,
        estimated_duration_seconds: estimateDurationSeconds(a.content),
        extraction_engine: "structured-v1",
      },
    }));
    const { error: insErr } = await supabase.from("articles").insert(rows);
    if (insErr) throw new Error(`articles insert: ${insErr.message}`);

    const totalArticles = (job.article_count ?? 0) + rows.length;
    const isLastPage = page >= job.total_pages;
    await supabase.from("processing_jobs").update({
      done_pages: page,
      article_count: totalArticles,
      // Every page can individually "succeed" (OCR + insert with 0 rows, or a
      // structuring fallback that still returns valid-but-empty JSON) while the
      // edition as a whole produced nothing usable — status must reflect the
      // final article count, not just "did the last page throw."
      status: isLastPage ? (totalArticles > 0 ? "completed" : "failed") : "processing",
      ...(isLastPage && totalArticles === 0
        ? { error: "OCR completed on every page but no articles were extracted." }
        : {}),
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);
    console.log(`[edition] job ${jobId} page ${page}/${job.total_pages}: ${rows.length} articles`);
  } catch (e) {
    const msg = (e as Error).message;
    console.warn(`[edition] page ${page} failed: ${msg}`);
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

  // chain next page, or finish: delete the source file (articles + audio are
  // the product; the source PDF is no longer needed — saves storage).
  if (page < job.total_pages) {
    fireContinuation(jobId, page + 1, geminiKey);
  } else {
    // All pages done — stitch cross-page article continuations, then clean up.
    await finalizeContinuations(supabase, job.newspaper_id, geminiKey, usage);
    await supabase.storage.from("uploads").remove([sourcePath])
      .then(() => {}, () => {});
    console.log(`[edition] job ${jobId} completed; source ${sourcePath} deleted`);
  }
}

// ── Cross-page continuation stitching ────────────────────────────────────────
// Telugu papers split long articles across pages: the body ends with a marker
// like "(మిగతా 3వ పేజీలో)" / "మిగతా 3లో" / "సశేషం 5వ పేజీలో", and the rest sits
// on page N under a "(... తరువాయి)" continuation header. This runs once, after
// every page is extracted (the only point all pages coexist). Conservative:
// only merges on a strong match (continuation header OR matching headline) to
// avoid fusing unrelated articles; otherwise it just strips the dangling marker
// so it isn't read aloud.

// "continued TO page N" — captures the page number.
const CONT_TO = /(?:మిగతా|సశేషం|తరువాయి)\s*\(?\s*(\d{1,2})\s*(?:వ\s*)?(?:పేజీలో|పేజీ|లో)[^)]*\)?/;
// "continued FROM" header at the start of the destination article.
const CONT_FROM = /(?:\d{1,2}\s*(?:వ\s*)?పేజీ|మొదటి\s*పేజీ)\s*తరువాయి/;

// Continuation-page headlines are often shortened from the original (trimmed
// to save space) — sometimes a prefix, sometimes a fragment lifted from
// elsewhere in the original headline, not always starting at character 0.
// Comparing a fixed 10-char slice for exact equality missed most real
// cases. Check whether the shorter (normalized) title appears ANYWHERE in
// the longer one, with a length floor so short titles can't false-positive
// on a shared common word.
function titleOverlapMatch(t1: string, t2: string): boolean {
  const n1 = (t1 ?? "").trim().replace(/\s+/g, " ");
  const n2 = (t2 ?? "").trim().replace(/\s+/g, " ");
  if (!n1 || !n2) return false;
  const [shorter, longer] = n1.length <= n2.length ? [n1, n2] : [n2, n1];
  if (shorter.length < 10) return false;
  return longer.includes(shorter);
}

// Fallback for when neither the CONT_FROM header nor titleOverlapMatch
// confidently resolves a match — the continuation headline may be a genuine
// paraphrase (same story, different wording) rather than a truncation,
// which no string comparison can catch. Only called for articles that
// already have a real "continued on page N" marker and at least one
// same-page candidate the deterministic checks left unresolved, so this
// stays rare and targeted rather than a call per article.
async function semanticContinuationMatch(
  sourceTitle: string,
  sourceBody: string,
  candidates: Array<{ title: string; body: string }>,
  geminiKey: string,
  ctx?: UsageCtx,
): Promise<number | null> {
  if (!geminiKey || !candidates.length) return null;
  const prompt =
    `A Telugu newspaper article says it continues on another page. Below is ` +
    `that article's headline + opening text, and a numbered list of candidate ` +
    `articles found on the target page. Decide which candidate (if any) is ` +
    `genuinely the CONTINUATION of the same story — same event, same ` +
    `people/place, picking up where the first part left off. Headlines are ` +
    `often reworded or shortened on the continuation page, so judge by ` +
    `CONTENT, not matching words.\n\n` +
    `Return ONLY JSON: {"match": <candidate index, or -1 if none confidently match>}\n\n` +
    `SOURCE:\nheadline: "${sourceTitle.slice(0, 80)}"\nopening: "${sourceBody.slice(0, 150)}"\n\n` +
    `CANDIDATES:\n${
      candidates
        .map((c, i) =>
          `[${i}] headline: "${c.title.slice(0, 80)}"\n    opening: "${c.body.slice(0, 150)}"`
        )
        .join("\n")
    }`;
  const { status, text } = await generate({
    tier: "fast",
    parts: [{ text: prompt }],
    apiKey: geminiKey,
    ctx,
  });
  if (status !== 200) return null;
  const data = JSON.parse((text.match(/\{[\s\S]*\}/) ?? ["{}"])[0]) as { match?: number };
  return typeof data.match === "number" && data.match >= 0 && data.match < candidates.length
    ? data.match
    : null;
}

// deno-lint-ignore no-explicit-any
async function finalizeContinuations(
  supabase: any, newspaperId: string, geminiKey: string, ctx?: UsageCtx,
): Promise<void> {
  if (!newspaperId) return;
  const { data: arts } = await supabase.from("articles")
    .select("id,title,full_content,content_preview,page_number")
    .eq("newspaper_id", newspaperId)
    .order("page_number");
  if (!arts || arts.length < 2) return;

  // ── Front-page teaser → stitch its headline onto the full story ───────────
  // Front pages carry short promo blurbs ("…full story on page 8") whose text is
  // echoed by the full article elsewhere. Rather than drop them, prepend the
  // teaser's headline (the front-page kicker) to the full article's headline so
  // the listener knows this was the front-page lead — then remove the blurb.
  const longs = (arts as Array<{ id: string; title: string; full_content: string }>)
    .filter((x) => (x.full_content?.length ?? 0) > 500);
  for (const a of arts as Array<{ id: string; title: string; full_content: string }>) {
    const body = a.full_content ?? "";
    if (body.length >= 260 || body.length < 30) continue;
    let match: { id: string; title: string; full_content: string } | undefined;
    for (const off of [0, 12, 24, 40, 60]) {
      const probe = body.slice(off, off + 18).trim();
      if (probe.length < 12) continue;
      match = longs.find((L) => L.id !== a.id && L.full_content.includes(probe));
      if (match) break;
    }
    if (!match) continue;
    const kicker = (a.title ?? "").trim();
    // Only stitch a clean, short kicker; otherwise just drop the blurb.
    if (kicker && kicker.length <= 36 && !(match.title ?? "").includes(kicker)) {
      await supabase.from("articles")
        .update({ title: `${kicker} — ${match.title}` }).eq("id", match.id);
      console.log(`[edition] stitched front-page kicker "${kicker}" → full story`);
    }
    await supabase.from("articles").delete().eq("id", a.id);
  }

  for (const a of arts) {
    const body: string = a.full_content ?? "";
    const m = body.match(CONT_TO);
    if (!m) continue;
    const targetPage = parseInt(m[1], 10);

    // candidate continuations: articles on the target page
    const cands = arts.filter((x: typeof a) =>
      x.page_number === targetPage && x.id !== a.id && x.full_content);
    let best: typeof a | null = null;
    let bestScore = 0;
    for (const c of cands) {
      const head = (c.full_content as string).slice(0, 90);
      let score = 0;
      if (CONT_FROM.test(head)) score += 2;
      if (titleOverlapMatch(a.title as string, c.title as string)) {
        score += 2;
      }
      if (score > bestScore) { bestScore = score; best = c; }
    }

    // Deterministic checks found nothing confident, but there's a real
    // "continued on page N" marker and at least one same-page candidate —
    // the continuation headline may be a paraphrase rather than a
    // truncation/overlap. Ask Gemini to judge by content instead of text.
    if (bestScore < 2 && cands.length) {
      const idx = await semanticContinuationMatch(
        a.title as string,
        body,
        cands.map((c: typeof a) => ({
          title: (c.title as string) ?? "",
          body: (c.full_content as string) ?? "",
        })),
        geminiKey,
        ctx,
      ).catch(() => null);
      if (idx !== null) {
        best = cands[idx];
        bestScore = 2;
        console.log(`[edition] semantic continuation match p→${targetPage}: "${(a.title as string).slice(0, 24)}"`);
      }
    }

    // Strip the dangling "continued to" marker from this article regardless.
    const head = body.replace(CONT_TO, " ").replace(/\s{2,}/g, " ").trim();

    if (best && bestScore >= 2) {
      const contBody = (best.full_content as string)
        .replace(CONT_FROM, " ")
        .replace(/^[\s\S]{0,40}?తరువాయి[^)]*\)?/, " ") // drop leading header line
        .replace(/\s{2,}/g, " ")
        .trim();
      const merged = `${head} ${contBody}`.trim();
      await supabase.from("articles")
        .update({ full_content: merged, content_preview: merged.slice(0, 200) })
        .eq("id", a.id);
      await supabase.from("articles").delete().eq("id", best.id);
      console.log(`[edition] merged continuation p→${targetPage}: "${(a.title as string).slice(0, 24)}"`);
    } else if (head !== body) {
      // No confident match — at least don't read the marker aloud.
      await supabase.from("articles")
        .update({ full_content: head, content_preview: head.slice(0, 200) })
        .eq("id", a.id);
    }
  }
}

function fireContinuation(jobId: string, page: number, geminiKey: string): void {
  const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/documents-process-edition`;
  // Anon JWT satisfies the gateway; the service key travels in x-internal-token
  // and is string-compared by our gate (it may be an opaque sb_secret_ key,
  // which is not a decodable JWT — see jwtRole).
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
    // The user's Gemini key rides along the internal continuation chain only —
    // it's never written to a table (processing_jobs has no such column).
    body: JSON.stringify({ job_id: jobId, page, geminiKey }),
  }).then(async (r) => {
    if (!r.ok) console.warn(`[edition] continuation page ${page} -> HTTP ${r.status}`);
    await r.body?.cancel();
  }).catch((e) => console.warn("[edition] continuation fire failed:", e.message));
  // deno-lint-ignore no-explicit-any
  (globalThis as any).EdgeRuntime?.waitUntil?.(p);
}

// ── Main ──────────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SERVICE_KEY || !Deno.env.get("SARVAM_API_KEY") || !Deno.env.get("GEMINI_API_KEY")) {
    return json({ error: "config_missing" }, 500);
  }
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

  const contentType = req.headers.get("content-type") ?? "";

  if (contentType.includes("application/json")) {
    const body = await req.json().catch(() => ({})) as {
      job_id?: string; page?: number; geminiKey?: string;
      storagePath?: string; filename?: string;
    };

    // ── internal continuation (service-key holders only) ──────────────────
    if (body.job_id && body.page) {
      const internal = req.headers.get("x-internal-token") ?? "";
      if (internal !== SERVICE_KEY && jwtRole(req) !== "service_role") {
        return json({ error: "forbidden" }, 403);
      }
      await processPage(supabase, body.job_id, body.page, body.geminiKey ?? "");
      return json({ ok: true, job_id: body.job_id, page: body.page });
    }

    // ── public: start from a pre-uploaded storage path (durable path) ─────
    if (body.storagePath) {
      return await runStart(supabase, req, SUPABASE_URL!,
        { storagePath: body.storagePath, filename: body.filename || "edition.pdf" });
    }
    return json({ error: "bad_request" }, 400);
  }

  // ── public: start from a multipart upload (legacy / small files) ────────
  return await runStart(supabase, req, SUPABASE_URL!, { multipart: true });
});

// Shared edition starter. Source is either a multipart file in the request, or
// a path the client already uploaded straight to storage (the durable path —
// the heavy byte transfer never touches this function).
async function runStart(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  req: Request,
  SUPABASE_URL: string,
  source: { multipart?: boolean; storagePath?: string; filename?: string },
): Promise<Response> {
  try {
    // Shared GatiVāni key — OCR/structuring runs on our own Gemini quota, not
    // BYOK. Presence is already guaranteed by the config_missing check at the
    // top of the handler; the rate limit below is what actually bounds cost
    // now that this isn't gated behind each caller bringing their own key.
    const userGeminiKey = Deno.env.get("GEMINI_API_KEY")!;

    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
    const oneHourAgo = new Date(Date.now() - 3600_000).toISOString();
    const { count } = await supabase
      .from("request_log").select("*", { count: "exact", head: true })
      .eq("ip", ip).eq("endpoint", "documents-process-edition")
      .gte("created_at", oneHourAgo);
    if ((count ?? 0) >= 20) {
      return json({ error: "rate_limited", message: "Edition limit: 20 per hour." }, 429);
    }
    await supabase.from("request_log").insert({ ip, endpoint: "documents-process-edition" });

    let originalName: string;
    let sourcePath: string;       // where the source lives in the uploads bucket
    let bytes: Uint8Array;        // normalized PDF bytes, for page counting

    if (source.multipart) {
      const form = await req.formData();
      const file = form.get("document");
      if (!(file instanceof File)) return json({ error: "missing_file" }, 400);
      if (file.size > 60 * 1024 * 1024) return json({ error: "file_too_large", message: "Max 60 MB." }, 413);
      originalName = file.name || "edition.pdf";
      const safe = originalName.replace(/[^a-zA-Z0-9._-]/g, "_");
      sourcePath = `editions/${Date.now()}_${safe}`;
      bytes = await normalizeToPdf(new Uint8Array(await file.arrayBuffer()));
      const { error: upErr } = await supabase.storage.from("uploads")
        .upload(sourcePath, bytes, { contentType: "application/pdf", upsert: true });
      if (upErr) throw new Error(`pdf store: ${upErr.message}`);
    } else {
      originalName = source.filename!;
      sourcePath = source.storagePath!;
      const { data: blob, error: dlErr } = await supabase.storage
        .from("uploads").download(sourcePath);
      if (dlErr) throw new Error(`source download: ${dlErr.message}`);
      bytes = await normalizeToPdf(new Uint8Array(await blob.arrayBuffer()));
    }

    const pdf = await PDFDocument.load(bytes);
    const totalPages = Math.min(pdf.getPageCount(), MAX_PAGES);
    if (totalPages === 0) return json({ error: "empty_pdf" }, 400);

    // Ground the edition's date in what's actually printed on page 1, so a
    // fresh scan of yesterday's paper doesn't get mislabeled/merged as today.
    const single = await PDFDocument.create();
    const [pg] = await single.copyPages(pdf, [0]);
    single.addPage(pg);
    const printedDate = await detectPrintedDate(await single.save(), userGeminiKey, {
      supabase,
      fn: "documents-process-edition",
    });
    const pubDate = printedDate || parseDateFromFilename(originalName) || todayIST();
    const title = originalName.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim();

    let newspaperId: string;
    const { data: existing } = await supabase
      .from("newspapers").select("id")
      .eq("title", title).eq("publication_date", pubDate).limit(1).maybeSingle();
    if (existing?.id) {
      newspaperId = existing.id;
      // Reprocessing the same edition: clear its old articles so we replace
      // rather than duplicate.
      await supabase.from("articles").delete().eq("newspaper_id", newspaperId);
    } else {
      const { data: created, error: nErr } = await supabase
        .from("newspapers")
        .insert({ title, publication_date: pubDate, language: "te" })
        .select("id").single();
      if (nErr) throw new Error(`newspaper insert: ${nErr.message}`);
      newspaperId = created.id;
    }

    const { data: jobRow, error: jErr } = await supabase
      .from("processing_jobs")
      .insert({
        filename: originalName, status: "processing",
        total_pages: totalPages, newspaper_id: newspaperId, source_path: sourcePath,
      })
      .select("id").single();
    if (jErr) throw new Error(`job insert: ${jErr.message}`);
    const jobId = jobRow.id as string;

    fireContinuation(jobId, 1, userGeminiKey);
    return json({ ok: true, jobId, newspaperId, totalPages, pubDate });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-process-edition]", err);
    return json({ error: "edition_failed", message }, 500);
  }
}
