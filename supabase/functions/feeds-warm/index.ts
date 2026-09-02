import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import * as r2 from "../_shared/r2.ts";

// feeds-warm — builds and pre-synthesizes the Live feed in batches.
//
// One tick does as much as it safely can and then returns; the schedule calls
// it often. The work is a small state machine per language:
//
//   no staging batch, last publish older than the interval → build one
//   staging batch with pending articles                    → drain some
//   staging batch drained (or past its deadline)           → publish it
//   batches retired long enough                            → drop their audio
//
// Nothing here is on a user's critical path, so it is allowed to be slow. What
// it must not be is greedy: the Gemini free tier is a few requests per minute,
// and the app's own on-demand synthesis shares that budget. Every call is
// therefore start-staggered at 60s/RPM and the tick stops at a wall-clock
// deadline well short of the edge runtime's limit.
//
// Scheduler-invoked, so there is no user JWT — it authenticates on CRON_SECRET,
// the same way storage-cleanup does.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-cron-secret",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Cadence ───────────────────────────────────────────────────────────────────
// Every knob is an env var with a request-body override. The env var is the
// standing setting (`supabase secrets set WARM_INTERVAL_MINUTES=180`); the body
// override exists so a manual run can try a value without a redeploy, and so
// the workflow can force a batch on demand.
//
// intervalMinutes does double duty on purpose: it is both how often a new batch
// starts AND the deadline by which the current one publishes whatever it has.
// That makes the cadence self-correcting — if synthesis can't keep up with the
// interval, the feed still turns over on time, just with fewer articles, rather
// than drifting further behind every cycle.
function num(v: unknown, fallback: number): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

interface Config {
  intervalMinutes: number;
  articles: number;
  rpm: number;
  tickSeconds: number;
  minArticles: number;
  maxAttempts: number;
  retireHours: number;
  langs: string[];
}

function config(body: Record<string, unknown>): Config {
  const env = Deno.env.get.bind(Deno.env);
  const langs = String(body.langs ?? env("WARM_LANGS") ?? "te")
    .split(",").map((s) => s.trim()).filter(Boolean);
  return {
    intervalMinutes: num(body.intervalMinutes ?? env("WARM_INTERVAL_MINUTES"), 120),
    articles: num(body.articles ?? env("WARM_ARTICLES"), 12),
    // Gemini free-tier requests per minute, shared with on-demand playback.
    rpm: num(body.rpm ?? env("WARM_RPM"), 3),
    // Wall-clock budget for one tick. Calls are started inside this window but
    // awaited past it, so keep it well under the edge runtime's ceiling: a
    // synthesis call itself can take ~50s.
    tickSeconds: num(body.tickSeconds ?? env("WARM_TICK_SECONDS"), 60),
    // Publish nothing at all below this many ready articles — a feed of two
    // stories is worse than the previous batch staying up another cycle.
    minArticles: num(body.minArticles ?? env("WARM_MIN_ARTICLES"), 4),
    maxAttempts: num(body.maxAttempts ?? env("WARM_MAX_ATTEMPTS"), 3),
    // How long a replaced batch's audio survives. Covers readers who were
    // mid-article when the swap happened; anything they saved into recent_plays
    // is exempted separately below.
    retireHours: num(body.retireHours ?? env("WARM_RETIRE_HOURS"), 24),
    langs,
  };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ── Article text ──────────────────────────────────────────────────────────────
// MUST match NewspaperArticle.spokenText in the Dart client exactly, character
// for character. documents-synthesize keys its cache on sha256(text), so a
// single differing space means the warmed audio is a cache MISS and the
// reader silently pays for on-demand synthesis anyway — with no error to notice.
// See packages/app/lib/models/newspaper_article.dart.
function spokenText(title: string, body: string, summary: string): string {
  const t = (title ?? "").trim();
  const b = ((body ?? "").trim() || (summary ?? "").trim());
  if (!t) return b;
  const sep = /[.?!।॥…]$/.test(t) ? "\n\n" : ".\n\n";
  return `${t}${sep}${b}`;
}

interface FeedItem {
  id: string;
  title: string;
  link: string;
  source: string;
  pubDate: string;
  summary: string;
  body: string;
}

// ── One article of synthesis ──────────────────────────────────────────────────
// Goes through documents-synthesize rather than calling the TTS provider
// directly, so the warmed audio lands in exactly the cache row
// (articles.audio_url, guarded by audio_text_hash) that the client will look in.
// Reimplementing synthesis here would mean two paths that have to agree forever.
//
// The service-role key is a valid JWT with no `sub`, so documents-synthesize's
// per-user rate limit does not apply — this job is budgeted by its own pacing.
async function synthesizeArticle(
  item: FeedItem,
  lang: string,
): Promise<{ audioUrl: string }> {
  const resp = await fetch(
    `${Deno.env.get("SUPABASE_URL")}/functions/v1/documents-synthesize`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        text: spokenText(item.title, item.body, item.summary),
        language: `${lang}-IN`,
        articleId: item.id,
        // Live articles carry no suggested speaker, so the client omits it too
        // and both sides land on the language default voice.
        readingStyle: "news_anchor",
      }),
      signal: AbortSignal.timeout(120_000),
    },
  );
  const data = await resp.json().catch(() => ({})) as Record<string, unknown>;
  if (!resp.ok || data.ok !== true) {
    throw new Error(
      `synthesize ${resp.status}: ${String(data.error ?? data.message ?? "unknown")}`,
    );
  }
  return { audioUrl: String(data.audioUrl ?? "") };
}

// deno-lint-ignore no-explicit-any
type Db = any;

// ── Build ─────────────────────────────────────────────────────────────────────
// `raw=1` asks feeds-articles for the live publisher fetch rather than the
// currently published batch — without it this job would re-stage the batch it
// just published, forever.
async function buildBatch(db: Db, lang: string, cfg: Config) {
  const resp = await fetch(
    `${Deno.env.get("SUPABASE_URL")}/functions/v1/feeds-articles?raw=1&lang=${lang}&limit=${cfg.articles}`,
    {
      headers: { Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}` },
      signal: AbortSignal.timeout(30_000),
    },
  );
  const data = await resp.json().catch(() => ({})) as Record<string, unknown>;
  const items = (Array.isArray(data.items) ? data.items : []) as FeedItem[];
  const usable = items.filter((i) => i?.id && (i.body ?? "").trim().length > 0);
  if (!usable.length) throw new Error("feeds-articles returned no usable items");

  const { data: batch, error } = await db.from("live_batches")
    .insert({ lang, status: "staging", items: usable }).select("id").single();
  if (error) throw new Error(`batch insert failed: ${error.message}`);

  const { error: qErr } = await db.from("live_batch_items").insert(
    usable.map((i) => ({ batch_id: batch.id, article_id: i.id })),
  );
  if (qErr) throw new Error(`queue insert failed: ${qErr.message}`);
  console.log(`[warm] ${lang}: staged batch ${batch.id} with ${usable.length} articles`);
  return { batchId: batch.id as string, items: usable };
}

// ── Drain ─────────────────────────────────────────────────────────────────────
async function drain(
  db: Db,
  batchId: string,
  lang: string,
  items: FeedItem[],
  cfg: Config,
  deadline: number,
): Promise<{ started: number; done: number; failed: number }> {
  const { data: pending } = await db.from("live_batch_items")
    .select("article_id, attempts")
    .eq("batch_id", batchId).eq("status", "pending")
    .lt("attempts", cfg.maxAttempts)
    .order("article_id");
  if (!pending?.length) return { started: 0, done: 0, failed: 0 };

  const byId = new Map(items.map((i) => [i.id, i]));
  const spacingMs = Math.ceil(60_000 / cfg.rpm);
  let done = 0, failed = 0;
  const inFlight: Promise<void>[] = [];

  for (const row of pending) {
    if (Date.now() >= deadline) break;
    // Stagger STARTS at the rate limit, and let the calls themselves overlap —
    // a call runs ~30-50s while the spacing is ~20s, so serialising them
    // outright would waste most of the budget the rate limit actually allows.
    if (inFlight.length) await sleep(spacingMs);
    if (Date.now() >= deadline) break;

    const item = byId.get(row.article_id);
    if (!item) continue;
    inFlight.push((async () => {
      try {
        const res = await synthesizeArticle(item, lang);
        await db.from("live_batch_items").update({
          status: "done",
          audio_url: res.audioUrl,
          attempts: row.attempts + 1,
          updated_at: new Date().toISOString(),
        }).eq("batch_id", batchId).eq("article_id", row.article_id);
        done++;
      } catch (e) {
        failed++;
        const attempts = row.attempts + 1;
        await db.from("live_batch_items").update({
          // Out of attempts means this article just won't make the batch;
          // publish filters it out rather than shipping a gap.
          status: attempts >= cfg.maxAttempts ? "failed" : "pending",
          attempts,
          error: String((e as Error).message ?? e).slice(0, 300),
          updated_at: new Date().toISOString(),
        }).eq("batch_id", batchId).eq("article_id", row.article_id)
        console.warn(`[warm] article ${row.article_id} failed:`, e);
      }
    })());
  }

  await Promise.all(inFlight);
  return { started: inFlight.length, done, failed };
}

// ── Ready set ─────────────────────────────────────────────────────────────────
// An article is ready once its narration came back. Anything short of that is
// exactly the un-narrated state this whole design exists to keep out of the feed.
async function readyArticleIds(db: Db, batchId: string): Promise<Set<string>> {
  const { data: rows } = await db.from("live_batch_items")
    .select("article_id").eq("batch_id", batchId).eq("status", "done");
  return new Set<string>((rows ?? []).map((r: { article_id: string }) => r.article_id));
}

// ── Publish ───────────────────────────────────────────────────────────────────
// The swap itself: the staging batch becomes what readers see, and whatever
// they were seeing becomes garbage on a timer. Only ready articles go into the
// payload, so "everything in the Live feed is fully narrated" holds even for a
// batch that partly failed.
async function publish(
  db: Db,
  batchId: string,
  lang: string,
  items: FeedItem[],
  cfg: Config,
): Promise<{ published: boolean; articles: number }> {
  const ready = await readyArticleIds(db, batchId);
  const readyItems = items.filter((i) => ready.has(i.id));
  if (readyItems.length < cfg.minArticles) {
    console.warn(
      `[warm] ${lang}: only ${readyItems.length} ready (< ${cfg.minArticles}) — retiring batch unpublished`,
    );
    await db.from("live_batches")
      .update({ status: "retired", retired_at: new Date().toISOString() })
      .eq("id", batchId);
    return { published: false, articles: readyItems.length };
  }

  await db.from("live_batches")
    .update({ status: "retired", retired_at: new Date().toISOString() })
    .eq("lang", lang).eq("status", "published");
  await db.from("live_batches").update({
    status: "published",
    published_at: new Date().toISOString(),
    items: readyItems,
  }).eq("id", batchId);
  // Drop the queue rows that never made it — the audio they point at doesn't
  // exist, and keeping them would confuse the retention pass below.
  await db.from("live_batch_items").delete()
    .eq("batch_id", batchId).neq("status", "done");
  console.log(`[warm] ${lang}: published batch ${batchId} with ${readyItems.length} articles`);
  return { published: true, articles: readyItems.length };
}

// ── Retention ─────────────────────────────────────────────────────────────────
// The payoff of double-buffering: a retired batch's audio is provably not in
// anyone's current feed, so it can go on a fixed delay instead of being swept
// for by age. The one exception is an article someone actually played —
// recent_plays keeps content resumable for 24h, and deleting the audio out from
// under a half-finished listen would 404 the resume. Same carve-out the seed
// fixtures get in the retention sweep.
async function collectGarbage(db: Db, cfg: Config): Promise<number> {
  const cutoff = new Date(Date.now() - cfg.retireHours * 3600_000).toISOString();
  const { data: batches } = await db.from("live_batches")
    .select("id").eq("status", "retired").lt("retired_at", cutoff).limit(20);
  if (!batches?.length) return 0;

  const ids = batches.map((b: { id: string }) => b.id);
  const { data: rows } = await db.from("live_batch_items")
    .select("article_id").in("batch_id", ids);
  if (!rows?.length) {
    await db.from("live_batches").delete().in("id", ids);
    return 0;
  }

  const articleIds = [...new Set(rows.map((r: { article_id: string }) => r.article_id))];
  const keep = new Set<string>();

  // A story that is still running routinely survives into the next batch — the
  // id is a hash of the publisher link, so it is literally the same article and
  // the same cached audio. Deleting on "this retired batch referenced it" would
  // therefore yank audio out of the batch currently on screen. Only ids that
  // appear in NO live batch are garbage.
  const { data: live } = await db.from("live_batches")
    .select("id").neq("status", "retired");
  if (live?.length) {
    const { data: stillUsed } = await db.from("live_batch_items")
      .select("article_id")
      .in("batch_id", live.map((b: { id: string }) => b.id))
      .in("article_id", articleIds);
    for (const r of stillUsed ?? []) keep.add(r.article_id);
  }

  // And an article someone actually played stays resumable for 24h via
  // recent_plays; deleting its audio would 404 the resume.
  const { data: keeps } = await db.from("recent_plays")
    .select("article_id").in("article_id", articleIds);
  for (const k of keeps ?? []) keep.add(k.article_id);

  // Path is reconstructed the same way documents-synthesize writes it for the
  // full-article target ("" suffix); a brief would be ".brief".
  const dead = [...new Set(
    articleIds.filter((id: string) => !keep.has(id)),
  )] as string[];
  const paths = dead.map((id) => `articles/${id}.wav`);

  let removed = 0;
  for (let i = 0; i < paths.length; i += 100) {
    const slice = paths.slice(i, i + 100);
    try {
      if (r2.configured()) {
        removed += await r2.remove(slice);
      } else {
        const { error } = await db.storage.from("audio").remove(slice);
        if (error) console.warn("[warm] audio remove failed:", error.message);
        else removed += slice.length;
      }
    } catch (e) {
      console.warn("[warm] audio remove failed:", e);
    }
  }
  // Clearing the cached URL is what makes a later play re-synthesize rather
  // than hand the player a URL that now 404s.
  if (dead.length) {
    await db.from("articles")
      .update({ audio_url: null, audio_text_hash: null }).in("id", dead);
  }
  await db.from("live_batches").delete().in("id", ids);
  console.log(`[warm] retention: removed ${removed} objects from ${ids.length} retired batch(es)`);
  return removed;
}

// ── Tick ──────────────────────────────────────────────────────────────────────
async function tickLang(db: Db, lang: string, cfg: Config, deadline: number, force: boolean) {
  const { data: staging } = await db.from("live_batches")
    .select("id, items, created_at").eq("lang", lang).eq("status", "staging")
    .order("created_at", { ascending: false }).limit(1).maybeSingle();

  if (!staging) {
    const { data: current } = await db.from("live_batches")
      .select("published_at").eq("lang", lang).eq("status", "published")
      .order("published_at", { ascending: false }).limit(1).maybeSingle();
    const ageMin = current?.published_at
      ? (Date.now() - Date.parse(current.published_at)) / 60_000
      : Infinity;
    if (!force && ageMin < cfg.intervalMinutes) {
      return { lang, action: "idle", nextInMinutes: Math.round(cfg.intervalMinutes - ageMin) };
    }
    const built = await buildBatch(db, lang, cfg);
    const res = await drain(db, built.batchId, lang, built.items, cfg, deadline);
    return {
      lang, action: "built", batchId: built.batchId,
      articles: built.items.length, ...res,
    };
  }

  const items = staging.items as FeedItem[];
  const res = await drain(db, staging.id, lang, items, cfg, deadline);

  const { count: left } = await db.from("live_batch_items")
    .select("*", { count: "exact", head: true })
    .eq("batch_id", staging.id).eq("status", "pending").lt("attempts", cfg.maxAttempts);
  const ageMin = (Date.now() - Date.parse(staging.created_at)) / 60_000;
  // Publish when the work is finished, or when the interval is up regardless —
  // a batch that can't finish in one interval publishes short rather than
  // letting the feed fall a whole cycle further behind on every turn.
  const overdue = ageMin >= cfg.intervalMinutes;
  if ((left ?? 0) === 0 || overdue) {
    const pub = await publish(db, staging.id, lang, items, cfg);
    return { lang, action: pub.published ? "published" : "discarded", overdue, ...res, ...pub };
  }
  return { lang, action: "draining", pendingArticles: left, ...res };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const secret = Deno.env.get("CRON_SECRET") ?? "";
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "unauthorized" }, 401);
  }

  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const cfg = config(body);
  const force = body.force === true;
  const deadline = Date.now() + cfg.tickSeconds * 1000;

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Conditional UPDATE returning zero rows means someone else holds the lock.
  // The lease is generous: a tick can legitimately run past its own deadline
  // waiting on in-flight synthesis calls.
  const holder = crypto.randomUUID();
  const lease = new Date(Date.now() + (cfg.tickSeconds + 180) * 1000).toISOString();
  const { data: claimed } = await db.from("live_warm_lock")
    .update({ locked_until: lease, holder })
    .eq("id", 1).lt("locked_until", new Date().toISOString())
    .select("holder").maybeSingle();
  if (!claimed) return json({ ok: true, skipped: "locked" });

  try {
    const results = [];
    for (const lang of cfg.langs) {
      try {
        results.push(await tickLang(db, lang, cfg, deadline, force));
      } catch (e) {
        console.error(`[warm] ${lang} failed:`, e);
        results.push({ lang, action: "error", message: String((e as Error).message ?? e) });
      }
    }
    const removed = await collectGarbage(db, cfg);
    return json({ ok: true, config: cfg, results, objectsRemoved: removed });
  } finally {
    // Release immediately rather than sitting on the remaining lease, so the
    // next scheduled tick isn't skipped for no reason.
    await db.from("live_warm_lock")
      .update({ locked_until: new Date().toISOString() })
      .eq("id", 1).eq("holder", holder);
  }
});
