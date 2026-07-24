// documents-review — re-judges articles the extraction pipeline held back as
// processing_status='review'. That flag was previously a dead end: computed
// during structuring, never revisited by anything (see the audit that led
// here — fetchEditionArticles/fetchArticleById gate on processing_status
// =ready, and nothing ever promotes a 'review' row afterward). This gives it
// an actual second pass: Gemini reads the flagged article plus its sibling
// titles on the same page, and decides whether it's genuinely complete and
// standalone or a partial/duplicate excerpt that should stay hidden.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { callGeminiJson } from "../_shared/structure.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-subscription-tier",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function jwtSub(req: Request): string {
  try {
    const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    return payload.sub ?? "";
  } catch {
    return "";
  }
}

// deno-lint-ignore no-explicit-any
async function checkUserRateLimit(supabase: any, userId: string): Promise<boolean> {
  // Batch-triggered, not per-article, so the cap is generous per call but
  // tight per hour — this is meant to be run occasionally, not polled.
  const oneHourAgo = new Date(Date.now() - 3600_000).toISOString();
  const { count } = await supabase
    .from("request_log").select("*", { count: "exact", head: true })
    .eq("ip", `user:${userId}`).eq("endpoint", "documents-review")
    .gte("created_at", oneHourAgo);
  if ((count ?? 0) >= 10) return false;
  await supabase.from("request_log").insert({ ip: `user:${userId}`, endpoint: "documents-review" });
  return true;
}

const MAX_BATCH = 50;
const CONTENT_SLICE = 3000;
const STAGGER_MS = 400;

function buildPrompt(
  title: string,
  content: string,
  flags: string[],
  siblings: Array<{ title: string }>,
): string {
  const siblingList = siblings.length
    ? siblings.map((s) => `- ${s.title || "(untitled)"}`).join("\n")
    : "(none)";
  return `You are proofreading one article extracted via OCR from a Telugu newspaper page. It was automatically flagged during extraction and held back from publishing — nobody has read it yet. Decide whether it's actually good enough to publish as narrated audio content.

Flags raised during extraction: ${flags.join(", ") || "(none recorded)"}

Other article titles already extracted from the SAME page (for duplicate detection):
${siblingList}

Article title: ${title || "(no title extracted)"}
Article content:
${content.slice(0, CONTENT_SLICE)}

Judge two things:
1. Is this a complete, coherent, standalone piece of news content — not cut off mid-sentence, not garbled OCR noise, not just a caption or photo credit fragment?
2. Is this a duplicate or partial subset of one of the sibling articles above (e.g. a pulled-out quote box or teaser whose full content already exists as a separate, longer article)?

Respond with ONLY this JSON, no other text: {"verdict": "ready" or "hold", "reason": "<one short sentence>"}
"ready" = complete, coherent, and NOT a duplicate/subset of a sibling — safe to publish.
"hold" = incomplete, garbled, or a duplicate/subset of a sibling — keep it hidden.`;
}

function normTitle(t: string): string {
  return t.replace(/\s+/g, " ").trim();
}

// Deterministic, not LLM-judged: exact-title duplicates within one edition
// are a reliable enough signal on their own, and cheaper/more trustworthy
// than asking Gemini to notice a sibling's title matches (it didn't,
// reliably, in testing — see the commit this shipped with). Runs across
// EVERY article regardless of current processing_status, because some
// duplicates were already sitting in 'ready' from the original extraction
// pass — a Gemini judgment pass over 'review' rows alone can't reach those.
// deno-lint-ignore no-explicit-any
async function dedupePass(
  supabase: any,
  newspaperId: string,
): Promise<{ duplicatesFound: number; duplicateIds: Set<string> }> {
  const { data: all } = await supabase
    .from("articles")
    .select("id, title, full_content, content_preview, processing_status, position_json")
    .eq("newspaper_id", newspaperId);

  const groups = new Map<string, typeof all>();
  for (const a of all ?? []) {
    const t = normTitle(a.title ?? "");
    if (!t) continue;
    const list = groups.get(t) ?? [];
    list.push(a);
    groups.set(t, list);
  }

  const duplicateIds = new Set<string>();
  for (const [, members] of groups) {
    if (members.length < 2) continue;
    const withLen = members.map((a) => ({
      a,
      len: (a.full_content || a.content_preview || "").length,
    }));
    withLen.sort((x, y) => y.len - x.len);
    const keptId = withLen[0].a.id;
    for (const { a } of withLen.slice(1)) {
      duplicateIds.add(a.id);
      const already = (a.position_json as Record<string, unknown> | null)?.dedup;
      if (already) continue; // already recorded by a prior run
      const newPositionJson = {
        ...(a.position_json as Record<string, unknown> ?? {}),
        dedup: { verdict: "duplicate", duplicate_of: keptId, reviewed_at: new Date().toISOString() },
      };
      await supabase.from("articles").update({
        processing_status: a.processing_status === "ready" ? "review" : a.processing_status,
        position_json: newPositionJson,
      }).eq("id", a.id);
    }
  }
  return { duplicatesFound: duplicateIds.size, duplicateIds };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY");
  if (!SUPABASE_URL || !SERVICE_KEY || !GEMINI_KEY) {
    return json({ error: "config_missing" }, 500);
  }
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

  const userId = jwtSub(req);
  if (userId && !(await checkUserRateLimit(supabase, userId))) {
    return json({ error: "rate_limited", message: "Review batch limit reached — try again later." }, 429);
  }

  const body = await req.json().catch(() => ({})) as { newspaperId?: string; limit?: number };
  const limit = Math.min(Math.max(body.limit ?? 20, 1), MAX_BATCH);

  // Dedup is edition-scoped (a title collision across two unrelated
  // newspapers means nothing), so it only runs when the caller passes one.
  let duplicatesFound = 0;
  let dedupedIds = new Set<string>();
  if (body.newspaperId) {
    const dedup = await dedupePass(supabase, body.newspaperId);
    duplicatesFound = dedup.duplicatesFound;
    dedupedIds = dedup.duplicateIds;
  }

  let query = supabase
    .from("articles")
    .select("id, title, full_content, content_preview, page_number, newspaper_id, position_json")
    .eq("processing_status", "review")
    .order("created_at", { ascending: true })
    .limit(limit);
  if (body.newspaperId) query = query.eq("newspaper_id", body.newspaperId);

  const { data: rawCandidates, error: fetchErr } = await query;
  if (fetchErr) return json({ error: "fetch_failed", message: fetchErr.message }, 500);
  // Skip anything dedupePass just demoted (or previously demoted) — asking
  // Gemini to judge a known duplicate wastes a call and risks exactly the
  // false "not a duplicate" verdict that motivated writing dedup at all.
  const candidates = (rawCandidates ?? []).filter((a) =>
    !dedupedIds.has(a.id) && !(a.position_json as Record<string, unknown> | null)?.dedup
  );
  if (candidates.length === 0) {
    return json({ ok: true, processed: 0, promoted: 0, held: 0, duplicatesFound, errors: [] });
  }

  let promoted = 0;
  let held = 0;
  const errors: Array<{ id: string; error: string }> = [];

  for (let i = 0; i < candidates.length; i++) {
    if (i > 0) await new Promise((r) => setTimeout(r, STAGGER_MS));
    const a = candidates[i];
    try {
      const { data: siblings } = await supabase
        .from("articles")
        .select("title")
        .eq("newspaper_id", a.newspaper_id)
        .eq("page_number", a.page_number)
        .neq("id", a.id)
        .limit(15);

      const flags: string[] = (a.position_json as Record<string, unknown> | null)?.review_flags as string[] ?? [];
      const content = (a.full_content || a.content_preview || "").trim();
      const prompt = buildPrompt(a.title ?? "", content, flags, siblings ?? []);

      const { status, text } = await callGeminiJson("gemini-2.5-flash-lite", [{ text: prompt }], GEMINI_KEY);
      if (status !== 200) throw new Error(`Gemini HTTP ${status}`);
      // Non-greedy/non-nested: the expected shape is flat ({"verdict":...,
      // "reason":...}), and Gemini occasionally emits two JSON blobs back to
      // back — a greedy \{[\s\S]*\} match swallows both into one invalid
      // parse. There's no nesting in this shape, so match just the first
      // {...} span.
      const match = text.match(/\{[^{}]*\}/);
      const parsed = JSON.parse(match ? match[0] : text) as { verdict?: string; reason?: string };

      const nowIso = new Date().toISOString();
      const geminiReview = { verdict: parsed.verdict, reason: parsed.reason, reviewed_at: nowIso };
      const newPositionJson = { ...(a.position_json as Record<string, unknown> ?? {}), gemini_review: geminiReview };

      if (parsed.verdict === "ready") {
        await supabase.from("articles").update({
          processing_status: "ready",
          quality_score: 0.85, // distinct from a clean 0.95 first pass — this one needed a second look
          position_json: newPositionJson,
        }).eq("id", a.id);
        promoted++;
      } else {
        await supabase.from("articles").update({ position_json: newPositionJson }).eq("id", a.id);
        held++;
      }
    } catch (e) {
      errors.push({ id: a.id, error: (e as Error).message });
    }
  }

  return json({ ok: true, processed: candidates.length, promoted, held, duplicatesFound, errors });
});
