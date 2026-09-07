// Process ONE page of an edition, then pull the next one.
//
//   POST { jobId, page, attempt }   (service role only)
//
// This is the worker. It is deliberately the only place that does expensive
// work, and it is idempotent per (job, page): the row was already moved to
// 'processing' by `claim_ingest_pages` before this was invoked, so a duplicate
// delivery finds nothing to claim and exits.
//
// Every exit path is terminal for the page — done, skipped, failed, or requeued
// — because the old chain's defining bug was a page that simply stopped and
// left the job hanging forever.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument } from "npm:pdf-lib@1.17.1";
import { extractArticlesStructured } from "../_shared/structure.ts";
import { estimateDurationSeconds, normalizeToPdf, ocrPageToHtml } from "../_shared/edition.ts";
import { rasterFirstPage } from "../_shared/raster.ts";
import {
  claimAndFire,
  failPage,
  fireAndForget,
  isServiceRole,
  jobCounts,
  logOcr,
  markJob,
  markPage,
  sha256Hex,
} from "../_shared/pipeline.ts";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * Copy a previously-extracted page's articles under this edition.
 *
 * The same physical page uploaded twice has identical OCR text. Re-running it
 * costs another Sarvam page and two or three Gemini calls to reproduce rows
 * already in the database.
 */
// deno-lint-ignore no-explicit-any
async function copyArticlesFrom(
  supabase: any,
  sourceNewspaperId: string,
  sourcePage: number,
  targetNewspaperId: string,
  targetPage: number,
): Promise<number> {
  const { data: src } = await supabase
    .from("articles")
    .select("title, content_preview, full_content, section, page_number, position_json, processing_status, quality_score")
    .eq("newspaper_id", sourceNewspaperId)
    .eq("page_number", sourcePage);
  const rows = (src ?? []) as Array<Record<string, unknown>>;
  if (!rows.length) return 0;

  const copies = rows.map((r) => ({
    ...r,
    newspaper_id: targetNewspaperId,
    page_number: targetPage,
    // Audio is cached per article id, and these are new ids, so the copies
    // start without audio. The text is identical, so the first listener
    // re-synthesises once and everyone after hits the cache.
    audio_url: null,
    summary_audio_url: null,
  }));
  const { error } = await supabase.from("articles").insert(copies);
  if (error) {
    console.warn("[pipeline-page] article copy failed:", error.message);
    return 0;
  }
  return copies.length;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  // Internal endpoint: without this, anyone could POST a job id and make us
  // burn OCR and model quota on demand.
  if (!isServiceRole(req)) return json({ error: "forbidden" }, 403);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const SARVAM = Deno.env.get("SARVAM_API_KEY")!;
  const GEMINI = Deno.env.get("GEMINI_API_KEY")!;
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

  const body = await req.json().catch(() => null) as
    { jobId?: string; page?: number; attempt?: number } | null;
  const jobId = body?.jobId ?? "";
  const page = Number(body?.page ?? 0);
  const attempt = Number(body?.attempt ?? 1);
  if (!jobId || !page) return json({ error: "missing_job_or_page" }, 400);

  const { data: job } = await supabase
    .from("ingest_jobs").select("*").eq("id", jobId).maybeSingle();
  if (!job) return json({ error: "job_not_found" }, 404);
  if (job.status === "failed") return json({ ok: true, skipped: "job failed" });

  const newspaperId = job.newspaper_id as string | null;
  const sourcePath = job.source_path as string;

  try {
    // ── Cut this page out of the source PDF ──────────────────────────────
    const { data: blob, error: dlErr } = await supabase.storage
      .from("uploads").download(sourcePath);
    if (dlErr) throw new Error(`pdf download: ${dlErr.message}`);
    const srcBytes = await normalizeToPdf(new Uint8Array(await blob.arrayBuffer()));
    const src = await PDFDocument.load(srcBytes);
    const single = await PDFDocument.create();
    const [pg] = await single.copyPages(src, [page - 1]);
    single.addPage(pg);
    const pageBytes = new Uint8Array(await single.save());

    // ── OCR ──────────────────────────────────────────────────────────────
    const ocrStart = Date.now();
    const html = await ocrPageToHtml(pageBytes, SARVAM);
    await logOcr(supabase, jobId, newspaperId, page, ocrStart);
    await markPage(supabase, jobId, page, { step: "ocr" });

    // ── Dedupe: has this exact page been extracted before? ───────────────
    const ocrHash = await sha256Hex(html);
    await markPage(supabase, jobId, page, { ocr_hash: ocrHash });

    if (newspaperId) {
      const { data: dup } = await supabase.rpc("find_duplicate_page", {
        p_hash: ocrHash,
        p_newspaper_id: newspaperId,
      });
      const match = Array.isArray(dup) ? dup[0] : null;
      if (match?.newspaper_id) {
        const copied = await copyArticlesFrom(
          supabase,
          match.newspaper_id as string,
          match.page as number,
          newspaperId,
          page,
        );
        if (copied > 0) {
          await markPage(supabase, jobId, page, {
            status: "skipped",
            step: "deduped",
            article_count: copied,
            claimed_at: null,
          });
          console.log(
            `[pipeline-page] job ${jobId} page ${page}: deduped, copied ${copied} articles`,
          );
          return await finishPage(supabase, jobId, page, copied);
        }
      }
    }

    // ── Structure ────────────────────────────────────────────────────────
    // Optionally send a downscaled JPEG instead of the page PDF; null when
    // RASTER_PAGES is off or rendering fails, in which case this is exactly
    // the old behaviour.
    const raster = await rasterFirstPage(pageBytes);
    const result = await extractArticlesStructured(
      html,
      raster ? raster.bytes : pageBytes,
      raster ? raster.mimeType : "application/pdf",
      GEMINI,
      { supabase, fn: "pipeline-page", jobId, newspaperId, page },
    );
    await markPage(supabase, jobId, page, { step: "structure" });

    // ── Insert ───────────────────────────────────────────────────────────
    // `reordered` records that Layer 2 successfully fixed a multi-column read
    // order — informational, not a defect, and gating on it hid clean articles
    // for no reason (most of a real edition's page 4 was `reordered`-only).
    // `low_coverage:*` is a whole-PAGE aggregate (how much of the page's OCR'd
    // text survived into ANY article), not a property of this one article; on
    // a dense real page it sits at 0.8-0.85 from ads and captions alone, which
    // then flagged every article on the page regardless of that article's own
    // completeness. An article this loose still hides for a real defect below.
    const isHardFlag = (f: string) => f !== "reordered" && !f.startsWith("low_coverage:");
    const rows = result.articles.map((a, i) => {
      const hardFlags = a.review.filter(isHardFlag);
      return {
      newspaper_id: newspaperId,
      title: a.title,
      content_preview: a.content.replace(/\n/g, " ").slice(0, 200),
      full_content: a.content,
      section: a.category || "News",
      page_number: result.printedPage ?? page,
      processing_status: hardFlags.length ? "review" : "ready",
      quality_score: hardFlags.length ? 0.7 : 0.95,
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
      };
    });

    if (rows.length) {
      const { error: insErr } = await supabase.from("articles").insert(rows);
      if (insErr) throw new Error(`articles insert: ${insErr.message}`);
    }

    await markPage(supabase, jobId, page, {
      status: "done",
      step: "insert",
      article_count: rows.length,
      claimed_at: null,
    });
    console.log(`[pipeline-page] job ${jobId} page ${page}: ${rows.length} articles`);
    return await finishPage(supabase, jobId, page, rows.length);
  } catch (e) {
    const message = (e as Error).message;
    await failPage(supabase, jobId, page, attempt, message);
    // Still pull the next page: one bad page must not stall the rest of the
    // edition, and the failed one is either requeued or already terminal.
    await claimAndFire(supabase, jobId, 1);
    return json({ ok: false, page, error: message }, 200);
  }
});

/**
 * Page finished. Claim the next one, and when every page is terminal, hand off
 * to finalize.
 *
 * The last worker to finish is the one that triggers finalize — no coordinator
 * is needed because `jobCounts` reads committed state.
 */
// deno-lint-ignore no-explicit-any
async function finishPage(
  supabase: any,
  jobId: string,
  page: number,
  articles: number,
): Promise<Response> {
  const started = await claimAndFire(supabase, jobId, 1);
  if (started === 0) {
    const counts = await jobCounts(supabase, jobId);
    if (counts.total > 0 && counts.terminal >= counts.total) {
      await markJob(supabase, jobId, {
        status: "stitching",
        article_count: counts.articles,
      });
      fireAndForget("pipeline-finalize", { jobId });
    }
  }
  return json({ ok: true, page, articles });
}
