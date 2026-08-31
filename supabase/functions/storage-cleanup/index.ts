import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-cron-secret",
};

// Drops synthesized audio older than RETENTION_DAYS and clears the rows that
// point at it, so the next play re-synthesizes instead of 404-ing on a dead
// public URL. Called by a scheduler, not by the app — a shared secret rather
// than a user JWT, since there is no user behind it.
const RETENTION_DAYS = Number(Deno.env.get("AUDIO_RETENTION_DAYS") ?? "30");
const BATCH = 100;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const secret = Deno.env.get("CRON_SECRET") ?? "";
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabase = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // `dryRun` reports what would go without touching anything — worth running
  // once after any change to the retention window.
  const body = await req.json().catch(() => ({}));
  const retentionDays = Number(body.retentionDays ?? RETENTION_DAYS);
  const dryRun = body.dryRun === true;

  const { data: stale, error } = await supabase.rpc("stale_audio_objects", {
    retention_days: retentionDays,
  });
  if (error) return json({ error: "lookup_failed", message: error.message }, 500);

  const paths: string[] = (stale ?? []).map((r: { name: string }) => r.name);
  if (dryRun) return json({ ok: true, dryRun: true, retentionDays, candidates: paths.length });

  const publicPrefix = `${supabaseUrl}/storage/v1/object/public/audio/`;
  let removed = 0;

  for (let i = 0; i < paths.length; i += BATCH) {
    const batch = paths.slice(i, i + BATCH);
    const { error: rmErr } = await supabase.storage.from("audio").remove(batch);
    if (rmErr) {
      console.warn("[cleanup] remove failed:", rmErr.message);
      continue;
    }
    removed += batch.length;

    // Only clear references once the objects are actually gone, so a failed
    // batch leaves the rows pointing at audio that still exists.
    const urls = batch.map((p) => publicPrefix + p);
    await supabase.from("article_chunks").delete().in("audio_url", urls);
    for (const table of ["articles", "edition_page_items"]) {
      await supabase.from(table).update({ audio_url: null }).in("audio_url", urls);
      await supabase.from(table).update({ summary_audio_url: null }).in("summary_audio_url", urls);
    }
  }

  console.log(`[cleanup] removed ${removed}/${paths.length} audio objects older than ${retentionDays}d`);
  return json({ ok: true, retentionDays, candidates: paths.length, removed });
});
