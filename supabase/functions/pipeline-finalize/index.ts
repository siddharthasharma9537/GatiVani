// Finish an edition: stitch cross-page continuations, tidy up, mark it ready.
//
//   POST { jobId }   (service role only)
//
// Runs once, after every page has reached a terminal state. Continuation
// stitching genuinely cannot run earlier: a Telugu daily splits a long article
// across pages ("మిగతా 3వ పేజీలో"), and merging needs both halves to exist, so
// this is the only point where the whole edition is present at once.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { finalizeContinuations } from "../_shared/edition.ts";
import { isServiceRole, jobCounts, markJob } from "../_shared/pipeline.ts";
import { prewarmEdition } from "../_shared/prewarm.ts";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!isServiceRole(req)) return json({ error: "forbidden" }, 403);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const GEMINI = Deno.env.get("GEMINI_API_KEY")!;
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

  const body = await req.json().catch(() => null) as { jobId?: string } | null;
  const jobId = body?.jobId ?? "";
  if (!jobId) return json({ error: "missing_job" }, 400);

  const { data: job } = await supabase
    .from("ingest_jobs").select("*").eq("id", jobId).maybeSingle();
  if (!job) return json({ error: "job_not_found" }, 404);

  // Idempotent: two workers can both observe "all pages terminal" and fire
  // this. Whoever arrives second finds the job already finished and stops,
  // rather than stitching the edition a second time.
  if (job.status === "ready" || job.status === "failed") {
    return json({ ok: true, alreadyFinished: job.status });
  }

  const counts = await jobCounts(supabase, jobId);
  if (counts.total === 0 || counts.terminal < counts.total) {
    // Fired early — a page is still running. The worker that finishes it will
    // fire this again.
    return json({ ok: true, deferred: true, terminal: counts.terminal, total: counts.total });
  }

  const newspaperId = job.newspaper_id as string | null;

  try {
    if (newspaperId && counts.articles > 0) {
      await finalizeContinuations(supabase, newspaperId, GEMINI, {
        supabase,
        fn: "pipeline-finalize",
        jobId,
        newspaperId,
      });
    }

    // Prewarm the stories people actually tap, inline, before the job is
    // reported ready. A daily paper lands at 5–6 am and is listened to by
    // 7–9, which is why this does not go through Gemini's cheaper Batch mode:
    // "within 24 hours" is an expiry, not a delivery time (plan §2.5).
    //
    // Best-effort. Prewarming is a latency optimisation — every article is
    // still synthesised on first play if it was missed — so a failure here
    // must never turn a good edition into a failed one.
    if (newspaperId && counts.articles > 0) {
      try {
        const pre = await prewarmEdition(supabase, newspaperId, jobId);
        console.log(
          `[pipeline-finalize] prewarmed ${pre.succeeded}/${pre.attempted} stories`,
        );
      } catch (e) {
        console.warn("[pipeline-finalize] prewarm failed:", (e as Error).message);
      }
    }

    // The source PDF has served its purpose — articles and audio are the
    // product. Keeping it grows the uploads bucket for nothing.
    if (job.source_path) {
      await supabase.storage.from("uploads").remove([job.source_path as string])
        .then(() => {}, () => {});
    }

    // An edition where every page failed is a failed edition, however
    // cleanly each individual page reported its failure.
    const succeeded = counts.articles > 0;
    await markJob(supabase, jobId, {
      status: succeeded ? "ready" : "failed",
      article_count: counts.articles,
      error: succeeded
        ? null
        : counts.failed > 0
        ? "Every page failed to process."
        : "OCR completed but no articles were extracted.",
    });

    console.log(
      `[pipeline-finalize] job ${jobId}: ${counts.articles} articles, ` +
        `${counts.failed} failed page(s) — ${succeeded ? "ready" : "failed"}`,
    );
    return json({
      ok: true,
      jobId,
      articles: counts.articles,
      failedPages: counts.failed,
      status: succeeded ? "ready" : "failed",
    });
  } catch (e) {
    const message = (e as Error).message;
    console.error("[pipeline-finalize]", e);
    // Stitching is a refinement, not the product: the articles are already
    // inserted and playable. Failing here must not throw away a good edition.
    await markJob(supabase, jobId, {
      status: counts.articles > 0 ? "ready" : "failed",
      article_count: counts.articles,
      error: `finalize: ${message.slice(0, 400)}`,
    });
    return json({ ok: false, message }, 200);
  }
});
