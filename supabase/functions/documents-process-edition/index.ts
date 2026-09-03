// DEPRECATED — forwards to pipeline-start.
//
// This function used to do the whole edition itself: split the PDF, then walk
// the pages one at a time by fetching itself for the next page. Two problems
// made it worth replacing rather than patching (Phase 3 of
// docs/ORCHESTRATION_PLAN.md):
//
//   * Serial. A 20-page daily took ~14 minutes because nothing overlapped.
//   * Not durable. If one invocation died — cold start, wall-clock limit, a
//     Sarvam poll that never returned — the chain stopped. The job sat at
//     "processing" forever, with no error recorded and a progress bar that
//     would never move again.
//
// The replacement is pipeline-start / pipeline-page / pipeline-finalize over
// the ingest_jobs + ingest_pages tables: pages run in parallel, each worker
// pulls the next one, and a cron sweep returns any page whose worker died.
//
// This shim exists only so already-deployed app builds keep working through
// the changeover. It accepts what it always accepted and returns the same
// shape, so an old client cannot tell the difference. Delete it once the
// clients in the wild are updated — the app calls pipeline-start directly as
// of this commit.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info, x-subscription-tier, x-user-gemini-key",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "config_missing" }, 500);

  console.log("[documents-process-edition] deprecated shim → pipeline-start");

  try {
    // Forward the body untouched: multipart and JSON both pass straight
    // through, and pipeline-start understands each. The caller's own
    // Authorization header is preserved so the job is still attributed to
    // whoever uploaded it, and x-forwarded-for so the rate limit still sees
    // the real client rather than this function.
    const headers: Record<string, string> = {
      "Authorization": req.headers.get("authorization") ?? `Bearer ${SERVICE_KEY}`,
    };
    const ct = req.headers.get("content-type");
    if (ct) headers["Content-Type"] = ct;
    const xff = req.headers.get("x-forwarded-for");
    if (xff) headers["x-forwarded-for"] = xff;

    // Buffer rather than stream: a streamed request body needs `duplex: "half"`,
    // which is not reliably supported across runtimes, and an edition PDF is
    // already bounded at 60 MB by the upload cap.
    const payload = await req.arrayBuffer();

    const resp = await fetch(`${SUPABASE_URL}/functions/v1/pipeline-start`, {
      method: "POST",
      headers,
      body: payload,
    });

    const text = await resp.text();
    return new Response(text, {
      status: resp.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    const message = (e as Error).message;
    console.error("[documents-process-edition] forward failed:", message);
    return json({ error: "edition_failed", message }, 500);
  }
});
