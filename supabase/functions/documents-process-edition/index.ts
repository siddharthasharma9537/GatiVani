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

// ── Page continuation ─────────────────────────────────────────────────────────

// deno-lint-ignore no-explicit-any
async function processPage(supabase: any, jobId: string, page: number): Promise<void> {
  const SARVAM = Deno.env.get("SARVAM_API_KEY")!;
  const GEMINI = Deno.env.get("GEMINI_API_KEY")!;

  const { data: job } = await supabase
    .from("processing_jobs").select("*").eq("id", jobId).single();
  if (!job || job.status === "failed") return;

  try {
    // load source PDF from storage and cut out this page
    const { data: blob, error: dlErr } = await supabase.storage
      .from("uploads").download(`editions/${jobId}.pdf`);
    if (dlErr) throw new Error(`pdf download: ${dlErr.message}`);
    const src = await PDFDocument.load(new Uint8Array(await blob.arrayBuffer()));
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
      page_number: page,
      processing_status: a.review.length ? "review" : "ready",
      quality_score: a.review.length ? 0.7 : 0.95,
      position_json: {
        article_index: i + 1,
        page,
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

  // chain next page
  if (page < job.total_pages) {
    fireContinuation(jobId, page + 1);
  } else {
    console.log(`[edition] job ${jobId} completed`);
  }
}

function fireContinuation(jobId: string, page: number): void {
  const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/documents-process-edition`;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  // fire-and-forget; the next invocation carries the work
  const p = fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${key}` },
    body: JSON.stringify({ job_id: jobId, page }),
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

  // ── internal continuation (service-role only) ───────────────────────────
  if (contentType.includes("application/json")) {
    if (jwtRole(req) !== "service_role") return json({ error: "forbidden" }, 403);
    const { job_id, page } = await req.json() as { job_id: string; page: number };
    if (!job_id || !page) return json({ error: "bad_request" }, 400);
    // do the page work inside this invocation; respond when done
    await processPage(supabase, job_id, page);
    return json({ ok: true, job_id, page });
  }

  // ── public: start a new edition job ─────────────────────────────────────
  try {
    // editions are ~20x the cost of a single page — tight rate limit
    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
    const oneHourAgo = new Date(Date.now() - 3600_000).toISOString();
    const { count } = await supabase
      .from("request_log").select("*", { count: "exact", head: true })
      .eq("ip", ip).eq("endpoint", "documents-process-edition")
      .gte("created_at", oneHourAgo);
    if ((count ?? 0) >= 2) {
      return json({ error: "rate_limited", message: "Edition limit: 2 per hour." }, 429);
    }
    await supabase.from("request_log").insert({ ip, endpoint: "documents-process-edition" });

    const form = await req.formData();
    const file = form.get("document");
    if (!(file instanceof File)) return json({ error: "missing_file" }, 400);
    if (file.size > 60 * 1024 * 1024) return json({ error: "file_too_large", message: "Max 60 MB." }, 413);

    const bytes = new Uint8Array(await file.arrayBuffer());
    const pdf = await PDFDocument.load(bytes);
    const totalPages = Math.min(pdf.getPageCount(), MAX_PAGES);
    if (totalPages === 0) return json({ error: "empty_pdf" }, 400);

    const originalName = file.name || "edition.pdf";
    const pubDate = parseDateFromFilename(originalName) || new Date().toISOString().split("T")[0];
    const title = originalName.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim();

    // newspaper row (reuse if same title+date already exists)
    let newspaperId: string;
    const { data: existing } = await supabase
      .from("newspapers").select("id")
      .eq("title", title).eq("publication_date", pubDate).limit(1).maybeSingle();
    if (existing?.id) {
      newspaperId = existing.id;
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
      .insert({ filename: originalName, status: "processing", total_pages: totalPages, newspaper_id: newspaperId })
      .select("id").single();
    if (jErr) throw new Error(`job insert: ${jErr.message}`);
    const jobId = jobRow.id as string;

    // store the source PDF where continuations can reach it
    const { error: upErr } = await supabase.storage
      .from("uploads")
      .upload(`editions/${jobId}.pdf`, bytes, { contentType: "application/pdf", upsert: true });
    if (upErr) throw new Error(`pdf store: ${upErr.message}`);
    const storageUrl = supabase.storage.from("uploads").getPublicUrl(`editions/${jobId}.pdf`).data.publicUrl;
    await supabase.from("newspapers").update({ storage_url: storageUrl }).eq("id", newspaperId);

    fireContinuation(jobId, 1);

    return json({
      ok: true,
      jobId,
      newspaperId,
      totalPages,
      statusHint: `poll GET ${SUPABASE_URL}/rest/v1/processing_jobs?id=eq.${jobId}&select=status,done_pages,total_pages,article_count,failed_pages`,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-process-edition]", err);
    return json({ error: "edition_failed", message }, 500);
  }
});
