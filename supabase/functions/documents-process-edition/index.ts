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
import { extractArticlesStructured } from "../_shared/structure.ts";

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
async function processPage(supabase: any, jobId: string, page: number): Promise<void> {
  const SARVAM = Deno.env.get("SARVAM_API_KEY")!;
  const GEMINI = Deno.env.get("GEMINI_API_KEY")!;

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

    const html = await ocrPageToHtml(new Uint8Array(pageBytes), SARVAM);
    const result = await extractArticlesStructured(
      html, new Uint8Array(pageBytes), "application/pdf", GEMINI);

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

    await supabase.from("processing_jobs").update({
      done_pages: page,
      article_count: (job.article_count ?? 0) + rows.length,
      status: page >= job.total_pages ? "completed" : "processing",
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);
    console.log(`[edition] job ${jobId} page ${page}/${job.total_pages}: ${rows.length} articles`);
  } catch (e) {
    const msg = (e as Error).message;
    console.warn(`[edition] page ${page} failed: ${msg}`);
    await supabase.from("processing_jobs").update({
      done_pages: page,
      failed_pages: [...(job.failed_pages ?? []), { page, error: msg.slice(0, 200) }],
      status: page >= job.total_pages ? "completed" : "processing",
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);
  }

  // chain next page, or finish: delete the source file (articles + audio are
  // the product; the source PDF is no longer needed — saves storage).
  if (page < job.total_pages) {
    fireContinuation(jobId, page + 1);
  } else {
    // All pages done — stitch cross-page article continuations, then clean up.
    await finalizeContinuations(supabase, job.newspaper_id);
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

// deno-lint-ignore no-explicit-any
async function finalizeContinuations(supabase: any, newspaperId: string): Promise<void> {
  if (!newspaperId) return;
  const { data: arts } = await supabase.from("articles")
    .select("id,title,full_content,content_preview,page_number")
    .eq("newspaper_id", newspaperId)
    .order("page_number");
  if (!arts || arts.length < 2) return;

  // ── Front-page teaser / digest drop ──────────────────────────────────────
  // Front pages carry short promo blurbs ("…full story on page 8") that are
  // print navigation, meaningless as audio. A SHORT article whose text is
  // echoed by a LONGER article elsewhere in the edition is a teaser — drop it.
  const longs = (arts as Array<{ id: string; full_content: string }>)
    .filter((x) => (x.full_content?.length ?? 0) > 500);
  for (const a of arts as Array<{ id: string; title: string; full_content: string }>) {
    const body = a.full_content ?? "";
    if (body.length >= 260 || body.length < 30) continue;
    let echoed = false;
    for (const off of [0, 12, 24, 40, 60]) {
      const probe = body.slice(off, off + 18).trim();
      if (probe.length < 12) continue;
      if (longs.some((L) => L.id !== a.id && L.full_content.includes(probe))) {
        echoed = true;
        break;
      }
    }
    if (echoed) {
      await supabase.from("articles").delete().eq("id", a.id);
      console.log(`[edition] dropped front-page teaser "${(a.title ?? "").slice(0, 20)}"`);
    }
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
      if (a.title && c.title &&
          (a.title as string).slice(0, 10) === (c.title as string).slice(0, 10)) {
        score += 2;
      }
      if (score > bestScore) { bestScore = score; best = c; }
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

function fireContinuation(jobId: string, page: number): void {
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
    body: JSON.stringify({ job_id: jobId, page }),
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
      job_id?: string; page?: number; storagePath?: string; filename?: string;
    };

    // ── internal continuation (service-key holders only) ──────────────────
    if (body.job_id && body.page) {
      const internal = req.headers.get("x-internal-token") ?? "";
      if (internal !== SERVICE_KEY && jwtRole(req) !== "service_role") {
        return json({ error: "forbidden" }, 403);
      }
      await processPage(supabase, body.job_id, body.page);
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

    const pubDate = parseDateFromFilename(originalName) || new Date().toISOString().split("T")[0];
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

    fireContinuation(jobId, 1);
    return json({ ok: true, jobId, newspaperId, totalPages });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-process-edition]", err);
    return json({ error: "edition_failed", message }, 500);
  }
}
