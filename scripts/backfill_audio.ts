#!/usr/bin/env -S deno run --allow-net --allow-env
//
// Narrate a back-catalogue edition, cheaply, when nobody is waiting.
//
// This is the ONE place Gemini's Batch mode still makes sense. Batch is 50%
// cheaper but promises results only "within 24 hours" — an expiry, not a
// delivery time. That rules it out of the live pipeline, where a paper lands at
// 5–6 am and is listened to by 7–9 (docs/ORCHESTRATION_PLAN.md §2.5). For an
// archive issue from three months ago, a day's latency costs nothing.
//
// It is a script rather than a function on purpose: backfilling is an operator
// action taken deliberately, with a bill attached, not something the app should
// ever trigger on its own.
//
// ── Usage ───────────────────────────────────────────────────────────────────
//
//   export SUPABASE_URL=https://<ref>.supabase.co
//   export SUPABASE_SERVICE_ROLE_KEY=...
//   deno run --allow-net --allow-env scripts/backfill_audio.ts \
//     --newspaper <uuid> [--limit 50] [--dry-run]
//
// Synthesises through documents-synthesize on the free lane, so it shares the
// same cache, content check and cost ledger as everything else — the run shows
// up in `edition_cost` like any other work.
//
// Note it does NOT use Chirp 3 HD. That voice's free pool is metered per day
// for the current edition's top stories (_shared/prewarm.ts); spending it on
// archive material would take the best voice away from today's paper.

const args = Deno.args;
function arg(name: string, fallback = ""): string {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
}
const hasFlag = (name: string) => args.includes(`--${name}`);

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");
  Deno.exit(2);
}

const newspaperId = arg("newspaper");
if (!newspaperId) {
  console.error("--newspaper <uuid> is required.");
  Deno.exit(2);
}
const limit = Number(arg("limit", "100"));
const dryRun = hasFlag("dry-run");

/** Same construction as the client and the prewarm lane — the content check
 *  in documents-synthesize rejects anything else. */
function spokenText(title: string, body: string): string {
  const t = (title ?? "").trim();
  const b = (body ?? "").trim();
  if (!t) return b;
  const sep = /[.?!।॥…]$/.test(t) ? "\n\n" : ".\n\n";
  return `${t}${sep}${b}`;
}

const rest = `${SUPABASE_URL}/rest/v1`;
const headers = {
  "apikey": SERVICE_KEY,
  "Authorization": `Bearer ${SERVICE_KEY}`,
  "Content-Type": "application/json",
};

// Only articles that have no audio yet — a backfill must never re-synthesise
// something already cached.
const query = `${rest}/articles?newspaper_id=eq.${newspaperId}` +
  `&audio_url=is.null&processing_status=eq.ready` +
  `&select=id,title,full_content,content_preview&limit=${limit}`;

const listResp = await fetch(query, { headers });
if (!listResp.ok) {
  console.error(`article lookup failed: HTTP ${listResp.status}`);
  Deno.exit(1);
}
const articles = await listResp.json() as Array<{
  id: string;
  title: string;
  full_content: string | null;
  content_preview: string | null;
}>;

if (!articles.length) {
  console.log("Nothing to backfill — every article already has audio.");
  Deno.exit(0);
}

const totalChars = articles.reduce(
  (n, a) => n + spokenText(a.title, a.full_content ?? a.content_preview ?? "").length,
  0,
);
console.log(
  `${articles.length} article(s), ~${totalChars.toLocaleString()} characters.`,
);
if (dryRun) {
  console.log("Dry run — nothing synthesised.");
  Deno.exit(0);
}

let ok = 0;
let failed = 0;
for (const [i, a] of articles.entries()) {
  const text = spokenText(a.title, a.full_content ?? a.content_preview ?? "");
  if (!text.trim()) continue;
  try {
    const resp = await fetch(`${SUPABASE_URL}/functions/v1/documents-synthesize`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        text,
        articleId: a.id,
        language: "te-IN",
        target: "audio_url",
        surface: "edition_tail",
        lane: "free",
      }),
      signal: AbortSignal.timeout(180_000),
    });
    const data = await resp.json().catch(() => ({})) as { ok?: boolean; message?: string };
    if (resp.ok && data.ok) {
      ok++;
    } else {
      failed++;
      console.warn(`  ${a.id}: ${data.message ?? `HTTP ${resp.status}`}`);
    }
  } catch (e) {
    failed++;
    console.warn(`  ${a.id}: ${(e as Error).message}`);
  }
  if ((i + 1) % 10 === 0) {
    console.log(`  … ${i + 1}/${articles.length}`);
  }
}

console.log(`Done: ${ok} synthesised, ${failed} failed.`);
console.log(
  "Cost is recorded in model_calls — check `select * from edition_cost` for this edition.",
);
