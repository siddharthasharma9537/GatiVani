// Begin ingesting an edition.
//
//   POST { sourcePath, filename }  →  { ok, jobId, totalPages }
//
// Splits nothing and processes nothing itself: it counts the pages, writes one
// `ingest_pages` row per page, and starts the first CONCURRENCY workers. That
// keeps this invocation short — it returns a job id in a second or two, and the
// client polls `ingest_job_progress` from there.
//
// Replaces the front half of documents-process-edition, which did the same work
// and then began a serial self-fetch chain through every page.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument } from "npm:pdf-lib@1.17.1";
import {
  bytesToBase64,
  normalizeToPdf,
  parseDateFromFilename,
  todayIST,
} from "../_shared/edition.ts";
import { generate } from "../_shared/gemini.ts";
import { claimAndFire, CONCURRENCY } from "../_shared/pipeline.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info, x-subscription-tier",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const MAX_PAGES = 24;

/** The caller's uid, when signed in — jobs are RLS-scoped to their owner. */
function jwtSub(req: Request): string | null {
  try {
    const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const payload = JSON.parse(
      atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")),
    );
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

/**
 * The date printed on page 1, so a fresh scan of yesterday's paper is not
 * merged into today's edition.
 */
async function detectPrintedDate(
  pageBytes: Uint8Array,
  geminiKey: string,
  // deno-lint-ignore no-explicit-any
  supabase: any,
  jobId: string,
): Promise<string> {
  try {
    const { status, text } = await generate({
      tier: "fast",
      parts: [
        { inline_data: { mime_type: "application/pdf", data: bytesToBase64(pageBytes) } },
        {
          text: "If a publication/issue date is printed on this newspaper page " +
            '(masthead or dateline), return it as YYYY-MM-DD. Otherwise return "". ' +
            'Return ONLY JSON: {"publicationDate":""}',
        },
      ],
      apiKey: geminiKey,
      maxOutputTokens: 256,
      timeoutMs: 20_000,
      ctx: { supabase, fn: "pipeline-start", jobId, page: 1 },
    });
    if (status !== 200) return "";
    const m = text.match(/"publicationDate"\s*:\s*"(\d{4}-\d{2}-\d{2})"/);
    return m ? m[1] : "";
  } catch (e) {
    console.warn("[pipeline-start] printed-date detection failed:", (e as Error).message);
    return "";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const SARVAM = Deno.env.get("SARVAM_API_KEY");
  const GEMINI = Deno.env.get("GEMINI_API_KEY");
  if (!SUPABASE_URL || !SERVICE_KEY || !SARVAM || !GEMINI) {
    return json({ error: "config_missing" }, 500);
  }
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

  let jobId = "";
  try {
    // Editions are the most expensive thing the app does — OCR plus several
    // model calls per page. The per-IP cap is what bounds that for anonymous
    // callers, and it is carried over from documents-process-edition unchanged.
    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
    const oneHourAgo = new Date(Date.now() - 3600_000).toISOString();
    const { count } = await supabase
      .from("request_log").select("*", { count: "exact", head: true })
      .eq("ip", ip).eq("endpoint", "pipeline-start")
      .gte("created_at", oneHourAgo);
    if ((count ?? 0) >= 20) {
      return json({ error: "rate_limited", message: "Edition limit: 20 per hour." }, 429);
    }
    await supabase.from("request_log").insert({ ip, endpoint: "pipeline-start" });

    // Two ways in: a multipart upload, or a path the client already wrote to
    // the uploads bucket directly (which avoids sending the PDF twice).
    const contentType = req.headers.get("content-type") ?? "";
    let sourcePath: string;
    let filename: string;
    let srcBytes: Uint8Array;

    if (contentType.includes("multipart/form-data")) {
      const form = await req.formData();
      const file = form.get("document");
      if (!(file instanceof File)) return json({ error: "missing_file" }, 400);
      if (file.size > 60 * 1024 * 1024) {
        return json({ error: "file_too_large", message: "Max 60 MB." }, 413);
      }
      filename = file.name || "edition.pdf";
      const safe = filename.replace(/[^a-zA-Z0-9._-]/g, "_");
      sourcePath = `editions/${Date.now()}_${safe}`;
      srcBytes = await normalizeToPdf(new Uint8Array(await file.arrayBuffer()));
      const { error: upErr } = await supabase.storage.from("uploads")
        .upload(sourcePath, srcBytes, { contentType: "application/pdf", upsert: true });
      if (upErr) throw new Error(`pdf store: ${upErr.message}`);
    } else {
      const body = await req.json().catch(() => null) as
        { sourcePath?: string; filename?: string } | null;
      sourcePath = body?.sourcePath ?? "";
      filename = body?.filename ?? "edition.pdf";
      if (!sourcePath) return json({ error: "missing_source_path" }, 400);
      const { data: blob, error: dlErr } = await supabase.storage
        .from("uploads").download(sourcePath);
      if (dlErr) return json({ error: "download_failed", message: dlErr.message }, 400);
      srcBytes = await normalizeToPdf(new Uint8Array(await blob.arrayBuffer()));
    }
    const pdf = await PDFDocument.load(srcBytes);
    const totalPages = Math.min(pdf.getPageCount(), MAX_PAGES);
    if (totalPages === 0) return json({ error: "empty_pdf" }, 400);

    // Create the job first, so a failure anywhere below is visible to the user
    // as a failed job rather than as silence.
    const { data: job, error: jobErr } = await supabase
      .from("ingest_jobs")
      .insert({
        user_id: jwtSub(req),
        filename,
        source_path: sourcePath,
        status: "splitting",
        total_pages: totalPages,
      })
      .select("id").single();
    if (jobErr || !job) {
      return json({ error: "job_create_failed", message: jobErr?.message }, 500);
    }
    jobId = job.id as string;

    // Date and title come from page 1.
    const first = await PDFDocument.create();
    const [pg] = await first.copyPages(pdf, [0]);
    first.addPage(pg);
    const printedDate = await detectPrintedDate(await first.save(), GEMINI, supabase, jobId);
    const pubDate = printedDate || parseDateFromFilename(filename) || todayIST();
    const title = filename.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim();

    // Reuse the newspaper row when this title+date already exists, so a
    // re-upload adds to the same edition instead of forking it.
    let newspaperId: string;
    const { data: existing } = await supabase
      .from("newspapers").select("id")
      .eq("title", title).eq("publication_date", pubDate).limit(1).maybeSingle();
    if (existing?.id) {
      newspaperId = existing.id as string;
      // Reprocessing the same title+date replaces rather than appends —
      // without this a re-upload doubles every article in the edition.
      await supabase.from("articles").delete().eq("newspaper_id", newspaperId);
    } else {
      const { data: created, error: npErr } = await supabase
        .from("newspapers")
        .insert({ title, publication_date: pubDate, language: "te" })
        .select("id").single();
      if (npErr || !created) throw new Error(`newspaper insert: ${npErr?.message}`);
      newspaperId = created.id as string;
    }

    // One row per page. This is the queue.
    const pageRows = Array.from({ length: totalPages }, (_, i) => ({
      job_id: jobId,
      page: i + 1,
      status: "queued",
    }));
    const { error: pagesErr } = await supabase.from("ingest_pages").insert(pageRows);
    if (pagesErr) throw new Error(`pages insert: ${pagesErr.message}`);

    await supabase.from("ingest_jobs")
      .update({ newspaper_id: newspaperId, status: "pages", updated_at: new Date().toISOString() })
      .eq("id", jobId);

    // Start the first batch. Each worker claims the next page as it finishes,
    // so the pipeline sustains itself from here without waiting on cron.
    const started = await claimAndFire(supabase, jobId, CONCURRENCY);
    console.log(
      `[pipeline-start] job ${jobId}: ${totalPages} pages, ${started} workers started`,
    );

    return json({ ok: true, jobId, totalPages, newspaperId, pubDate, started });
  } catch (e) {
    const message = (e as Error).message;
    console.error("[pipeline-start]", e);
    if (jobId) {
      await supabase.from("ingest_jobs")
        .update({ status: "failed", error: message.slice(0, 500) })
        .eq("id", jobId);
    }
    return json({ error: "start_failed", message }, 500);
  }
});
