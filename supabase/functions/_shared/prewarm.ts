// Prewarm the stories people actually tap, the moment an edition is ready.
//
// ── Why not Gemini Batch ────────────────────────────────────────────────────
// The plan originally prewarmed overnight on Gemini's Batch mode for the 50%
// discount. That is wrong for a daily newspaper: the paper lands at 5–6 am and
// commuters listen between 7 and 9. Batch promises results "within 24 hours",
// which is an expiry, not a delivery time — a job submitted at 6 am may return
// at 6:15, or at 5 am tomorrow. Nothing on that clock can be scheduled against
// it.
//
// Running inline on Cloud TTS instead is ready about a minute after ingest,
// costs nothing inside the free pool, and uses Chirp 3 HD — Google's most
// natural tier, better than the Gemini voice it replaces. Faster, cheaper and
// better, which is a rare combination and worth the note. Full reasoning:
// docs/ORCHESTRATION_PLAN.md §2.5.
//
// ── The guard that matters ──────────────────────────────────────────────────
// Chirp 3 HD is $30/1M characters past its 1M/month free pool — 7.5× WaveNet.
// It must never be paid for. So spend is metered as a DAILY allowance
// (1M ÷ 31 ≈ 32k characters) rather than a monthly one: a monthly budget would
// let a few large editions drain the pool by the 10th and leave the rest of the
// month on a different voice mid-way. When the day's allowance is gone the
// remaining stories fall back to WaveNet, never to paid Chirp.

import { voiceForSurface } from "./cloud_tts.ts";

/** Characters of Chirp 3 HD allowed per day. 1M/month ÷ 31, rounded down. */
export const DAILY_CHIRP_CHARS = Number(
  Deno.env.get("DAILY_CHIRP_CHARS") ?? "32000",
);

/** Top stories to prewarm per section. */
export const STORIES_PER_SECTION = Number(
  Deno.env.get("PREWARM_PER_SECTION") ?? "3",
);

/** How many synthesis requests to run at once. */
const CONCURRENCY = 5;

export interface TopStory {
  id: string;
  title: string;
  body: string;
  section: string;
  chars: number;
}

/**
 * The spoken form of an article.
 *
 * Must match `NewspaperArticle.spokenText` in the Flutter client character for
 * character: documents-synthesize verifies submitted text against the stored
 * article before it will write to the shared cache, and a mismatch here would
 * be rejected as content tampering — correctly, but unhelpfully.
 */
export function spokenText(title: string, body: string): string {
  const t = (title ?? "").trim();
  const b = (body ?? "").trim();
  if (!t) return b;
  const sep = /[.?!।॥…]$/.test(t) ? "\n\n" : ".\n\n";
  return `${t}${sep}${b}`;
}

/**
 * Characters of Chirp 3 HD already synthesised today, read from the cost
 * ledger. UTC day, matching how the ledger stores timestamps — the boundary
 * only has to be consistent, not local.
 */
// deno-lint-ignore no-explicit-any
export async function chirpCharsUsedToday(supabase: any): Promise<number> {
  const since = new Date();
  since.setUTCHours(0, 0, 0, 0);
  const { data, error } = await supabase
    .from("model_calls")
    .select("chars")
    .eq("kind", "tts")
    .like("model", "%Chirp3-HD%")
    .gte("created_at", since.toISOString());
  if (error) {
    // Unknown spend is treated as spent. Failing closed here risks a slightly
    // worse voice; failing open risks a bill at $30/1M.
    console.warn("[prewarm] allowance lookup failed, assuming exhausted:", error.message);
    return Number.MAX_SAFE_INTEGER;
  }
  return (data ?? []).reduce(
    (n: number, r: { chars: number | null }) => n + (r.chars ?? 0),
    0,
  );
}

/**
 * Pick the stories worth prewarming.
 *
 * Prominence in a printed newspaper is positional: the front page leads, and
 * within a page the extraction engine numbers articles in reading order. So
 * rank by page, then by position on it, then by length as a tie-break — a
 * two-line brief is rarely the story of the day. Articles flagged for review
 * are skipped: prewarming a mis-extracted article spends the best voice on
 * text that may be wrong.
 */
// deno-lint-ignore no-explicit-any
export async function selectTopStories(
  supabase: any,
  newspaperId: string,
  perSection = STORIES_PER_SECTION,
): Promise<TopStory[]> {
  const { data, error } = await supabase
    .from("articles")
    .select("id, title, full_content, content_preview, section, page_number, position_json")
    .eq("newspaper_id", newspaperId)
    .eq("processing_status", "ready")
    .order("page_number", { ascending: true });
  if (error) {
    console.warn("[prewarm] article lookup failed:", error.message);
    return [];
  }

  const rows = (data ?? []) as Array<Record<string, unknown>>;
  const bySection = new Map<string, Array<{ row: Record<string, unknown>; rank: number[] }>>();

  for (const row of rows) {
    const body = String(row.full_content ?? row.content_preview ?? "").trim();
    if (body.length < 200) continue; // too short to be worth a premium voice
    const section = String(row.section ?? "News");
    const page = Number(row.page_number ?? 99);
    const idx = Number(
      (row.position_json as Record<string, unknown> | null)?.article_index ?? 99,
    );
    const list = bySection.get(section) ?? [];
    // Negative length so a longer article sorts ahead at equal position.
    list.push({ row, rank: [page, idx, -body.length] });
    bySection.set(section, list);
  }

  const picked: TopStory[] = [];
  for (const [section, list] of bySection) {
    list.sort((a, b) => {
      for (let i = 0; i < a.rank.length; i++) {
        if (a.rank[i] !== b.rank[i]) return a.rank[i] - b.rank[i];
      }
      return 0;
    });
    for (const { row } of list.slice(0, perSection)) {
      const body = String(row.full_content ?? row.content_preview ?? "").trim();
      const title = String(row.title ?? "").trim();
      picked.push({
        id: String(row.id),
        title,
        body,
        section,
        chars: spokenText(title, body).length,
      });
    }
  }

  // Front-page stories first overall, so if the allowance runs out mid-edition
  // it runs out on the least prominent stories rather than arbitrary ones.
  picked.sort((a, b) => a.chars - b.chars);
  return picked;
}

export interface PrewarmResult {
  attempted: number;
  succeeded: number;
  chirpChars: number;
  wavenetChars: number;
  skipped: number;
}

/**
 * Synthesise the selected stories, in parallel, into the shared audio cache.
 *
 * Goes through documents-synthesize rather than calling Cloud TTS directly so
 * there is exactly one path that writes cached audio — same storage, same
 * text-hash content check, same ledger row. A second code path writing the
 * same cache is how caches quietly diverge.
 */
// deno-lint-ignore no-explicit-any
export async function prewarmEdition(
  supabase: any,
  newspaperId: string,
  jobId: string,
): Promise<PrewarmResult> {
  const result: PrewarmResult = {
    attempted: 0,
    succeeded: 0,
    chirpChars: 0,
    wavenetChars: 0,
    skipped: 0,
  };

  const stories = await selectTopStories(supabase, newspaperId);
  if (!stories.length) return result;

  const usedToday = await chirpCharsUsedToday(supabase);
  let remaining = Math.max(0, DAILY_CHIRP_CHARS - usedToday);
  console.log(
    `[prewarm] ${stories.length} stories; Chirp allowance ${remaining}/${DAILY_CHIRP_CHARS} chars left today`,
  );

  const chirpVoice = voiceForSurface("edition_top");
  const fallbackVoice = voiceForSurface("live_article"); // WaveNet
  const base = `${Deno.env.get("SUPABASE_URL")}/functions/v1/documents-synthesize`;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  // Decide every voice up front, single-threaded, so concurrent workers cannot
  // race the allowance and collectively overspend it.
  const plan = stories.map((s) => {
    const useChirp = s.chars <= remaining;
    if (useChirp) {
      remaining -= s.chars;
      result.chirpChars += s.chars;
    } else {
      result.wavenetChars += s.chars;
    }
    return { story: s, voice: useChirp ? chirpVoice : fallbackVoice };
  });

  async function run(item: { story: TopStory; voice: string }): Promise<void> {
    result.attempted++;
    try {
      const resp = await fetch(base, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${serviceKey}`,
        },
        body: JSON.stringify({
          text: spokenText(item.story.title, item.story.body),
          articleId: item.story.id,
          language: "te-IN",
          target: "audio_url",
          surface: "edition_top",
          lane: "free",
          // Honoured for service-role callers only; the allowance above is
          // what decides it.
          voice: item.voice,
        }),
        signal: AbortSignal.timeout(120_000),
      });
      if (!resp.ok) {
        console.warn(`[prewarm] ${item.story.id}: HTTP ${resp.status}`);
        await resp.body?.cancel();
        return;
      }
      const data = await resp.json() as { ok?: boolean };
      if (data.ok) result.succeeded++;
    } catch (e) {
      console.warn(`[prewarm] ${item.story.id} failed:`, (e as Error).message);
    }
  }

  // Bounded parallelism: fast enough to finish in about a minute, gentle
  // enough to stay under Chirp 3 HD's 200 requests/minute project limit.
  let cursor = 0;
  const workers = Array.from({ length: Math.min(CONCURRENCY, plan.length) }, async () => {
    while (cursor < plan.length) {
      const item = plan[cursor++];
      await run(item);
    }
  });
  await Promise.all(workers);

  console.log(
    `[prewarm] job ${jobId}: ${result.succeeded}/${result.attempted} stories ` +
      `(${result.chirpChars} Chirp chars, ${result.wavenetChars} WaveNet chars)`,
  );
  return result;
}
