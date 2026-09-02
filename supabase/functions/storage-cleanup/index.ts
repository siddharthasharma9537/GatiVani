import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import * as r2 from "../_shared/r2.ts";

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

  // R2 keeps no metadata in Postgres, so the candidate list comes from the
  // bucket listing rather than the stale_audio_objects lookup. Both paths
  // produce the same thing: keys older than the retention window.
  let paths: string[];
  if (r2.configured()) {
    const cutoff = Date.now() - retentionDays * 86_400_000;
    const objects = await r2.list("");
    paths = objects
      .filter((o) => o.lastModified.getTime() < cutoff)
      .map((o) => o.key);
  } else {
    const { data: stale, error } = await supabase.rpc("stale_audio_objects", {
      retention_days: retentionDays,
    });
    if (error) return json({ error: "lookup_failed", message: error.message }, 500);
    paths = (stale ?? []).map((r: { name: string }) => r.name);
  }
  if (dryRun) return json({ ok: true, dryRun: true, retentionDays, candidates: paths.length });

  const usingR2 = r2.configured();
  // The URL prefix has to match whichever store the objects were written to,
  // or the reference-clearing below silently matches nothing.
  const publicPrefix = usingR2
    ? ""
    : `${supabaseUrl}/storage/v1/object/public/audio/`;
  let removed = 0;

  for (let i = 0; i < paths.length; i += BATCH) {
    const batch = paths.slice(i, i + BATCH);
    if (usingR2) {
      const n = await r2.remove(batch);
      if (n === 0) continue;
      removed += n;
    } else {
      const { error: rmErr } = await supabase.storage.from("audio").remove(batch);
      if (rmErr) {
        console.warn("[cleanup] remove failed:", rmErr.message);
        continue;
      }
      removed += batch.length;
    }

    // Only clear references once the objects are actually gone, so a failed
    // batch leaves the rows pointing at audio that still exists.
    const urls = batch.map((p) => (usingR2 ? r2.publicUrl(p) : publicPrefix + p));
    for (const table of ["articles", "edition_page_items"]) {
      await supabase.from(table).update({ audio_url: null }).in("audio_url", urls);
      await supabase.from(table).update({ summary_audio_url: null }).in("summary_audio_url", urls);
    }
  }

  console.log(`[cleanup] removed ${removed}/${paths.length} audio objects older than ${retentionDays}d`);
  return json({ ok: true, retentionDays, candidates: paths.length, removed });
});
