// Progress for one ingest job.
//
//   GET|POST { jobId }  →  { ok, status, donePages, totalPages, ... }
//
// Why an endpoint rather than letting the app read `ingest_job_progress`
// directly: an edition can be uploaded without signing in, and those jobs have
// no owner, so there is no row-level policy that could let the uploader read
// their own job without also letting everyone read everyone's. Reading through
// here keeps the tables locked to their owners while still working for
// anonymous uploads.
//
// The job id is the capability. It is a v4 uuid handed only to whoever started
// the job, so knowing one is the proof of ownership — the same model as an
// unguessable share link. Nothing here lets a caller enumerate jobs, and the
// response carries no PII.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "config_missing" }, 500);

  let jobId = new URL(req.url).searchParams.get("jobId") ?? "";
  if (!jobId && req.method === "POST") {
    const body = await req.json().catch(() => null) as { jobId?: string } | null;
    jobId = body?.jobId ?? "";
  }
  // Reject anything that is not a uuid before it reaches the database: the
  // capability argument above only holds while the id space is unguessable.
  if (!UUID.test(jobId)) return json({ error: "invalid_job_id" }, 400);

  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data, error } = await supabase
    .from("ingest_job_progress")
    .select(
      "status, done_pages, total_pages, failed_pages, deduped_pages, article_count, newspaper_id, error",
    )
    .eq("id", jobId)
    .maybeSingle();

  if (error) return json({ error: "lookup_failed", message: error.message }, 500);
  if (!data) return json({ error: "job_not_found" }, 404);

  return json({
    ok: true,
    status: data.status,
    donePages: Number(data.done_pages ?? 0),
    totalPages: Number(data.total_pages ?? 0),
    failedPages: Number(data.failed_pages ?? 0),
    dedupedPages: Number(data.deduped_pages ?? 0),
    articleCount: Number(data.article_count ?? 0),
    newspaperId: data.newspaper_id,
    error: data.error,
  });
});
