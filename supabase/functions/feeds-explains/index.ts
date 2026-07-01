import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// feeds-explains — "GatiVani Take": an original Telugu explainer for the
// day's single most newsworthy story, national or international.
//
// Legal grounding (same principle as cricket-live): facts are not
// copyrightable, only their specific expression is. So this function never
// translates or reproduces any publisher's actual sentences — it collects
// HEADLINES ONLY (title + source + date, the same shape feeds-news already
// exposes) from multiple independent outlets covering the same event, and
// asks Gemini to write a fresh Telugu title + explainer grounded ONLY in the
// facts those headlines state. If the headlines don't carry enough detail,
// the model is instructed to stay brief rather than invent anything.
//
// Weight-to-article mechanism:
//   1. Pull ~60 candidate headlines: Telugu (national/politics/business) via
//      Google News' Telugu edition, English (world/business) via Google
//      News' English edition — the same India-relevant international lens
//      the user asked for (wars, elections, disasters, pandemics, tariffs on
//      India, major investments, trade deals, welfare schemes), not just
//      "trending anywhere."
//   2. Score every headline with keyword weights (see WEIGHTS below) —
//      deterministic, instant, no AI call.
//   3. Take the top scorer, gather other headlines (different source) that
//      corroborate the same story, and send just those as facts to Gemini.
//   4. Cache the pick for 10 minutes so this doesn't recompute on every load.
//
// Env: GEMINI_API_KEY (already configured, shared with other functions).

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=600",
    },
  });
}

function decode(s: string): string {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;|&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(parseInt(n, 10)))
    .replace(/&amp;/g, "&")
    .trim();
}

function pick(block: string, tag: string): string {
  const m = block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`));
  return m ? decode(m[1]) : "";
}

interface Headline {
  title: string;
  source: string;
  pubDate: string;
  lang: "te" | "en";
}

function parseItems(xml: string, lang: "te" | "en", limit: number): Headline[] {
  const out: Headline[] = [];
  const re = /<item>([\s\S]*?)<\/item>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null && out.length < limit) {
    const block = m[1];
    const source = pick(block, "source");
    let title = pick(block, "title");
    if (source && title.endsWith(` - ${source}`)) {
      title = title.slice(0, -(source.length + 3)).trim();
    }
    if (!title) continue;
    out.push({ title, source, pubDate: pick(block, "pubDate"), lang });
  }
  return out;
}

async function fetchGoogleNews(
  url: string,
  lang: "te" | "en",
  limit: number,
): Promise<Headline[]> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 10_000);
  try {
    const r = await fetch(url, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)" },
      signal: ctrl.signal,
    });
    if (!r.ok) return [];
    return parseItems(await r.text(), lang, limit);
  } catch {
    return [];
  } finally {
    clearTimeout(t);
  }
}

// Telugu, India locale — same as feeds-news.
const TE_LOCALE = "hl=te&gl=IN&ceid=IN:te";
const TE_TOPICS: Record<string, string> = {
  top: "",
  national: "భారతదేశం",
  business: "వ్యాపారం స్టాక్ మార్కెట్",
  politics: "రాజకీయాలు",
};
function teFeedUrl(topic: string): string {
  const q = TE_TOPICS[topic];
  return q
    ? `https://news.google.com/rss/search?q=${encodeURIComponent(q)}&${TE_LOCALE}`
    : `https://news.google.com/rss?${TE_LOCALE}`;
}

// English, US locale, Google News' topic-section shortcuts (redirect to the
// real feed — Deno's fetch follows redirects automatically).
const EN_LOCALE = "hl=en-US&gl=US&ceid=US:en";
const EN_TOPIC_URLS = [
  `https://news.google.com/rss/headlines/section/topic/WORLD?${EN_LOCALE}`,
  `https://news.google.com/rss/headlines/section/topic/BUSINESS?${EN_LOCALE}`,
];

// ── Weight-to-article scoring ────────────────────────────────────────────
// Each entry: [keywords (lowercased, matched as substrings), weight].
// Telugu keywords are matched against the raw title (Telugu script is
// case-less, no lowercasing needed); English keywords are matched against
// the lowercased title.
const POSITIVE_WEIGHTS: Array<{ words: string[]; weight: number }> = [
  // Tier 1 — crisis, disaster, pandemic.
  {
    weight: 40,
    words: [
      "war", "killed", "deaths", "dead", "earthquake", "flood", "cyclone",
      "tsunami", "wildfire", "collapse", "explosion", "attack", "invasion",
      "outbreak", "epidemic", "pandemic", "ebola", "virus spreads", "disaster",
      "యుద్ధం", "మృతి", "మరణాలు", "భూకంపం", "వరదలు", "తుఫాను", "పేలుడు",
      "దాడి", "అంటువ్యాధి", "మహమ్మారి", "ప్రమాదం",
    ],
  },
  // Tier 2 — political upheaval, elections.
  {
    weight: 30,
    words: [
      "election result", "resigns", "resignation", "coup", "no-confidence",
      "no confidence", "verdict", "reshuffle", "impeachment",
      "ఎన్నికల ఫలితాలు", "రాజీనామా", "తీర్పు", "మంత్రివర్గ", "అవిశ్వాస",
    ],
  },
  // Tier 3a — tariffs/trade/tax touching India.
  {
    weight: 28,
    words: [
      "tariff", "import duty", "export duty", "trade war", "sanctions",
      "free trade agreement", "trade deal", "trade pact", "duty waived",
      "సుంకం", "పన్ను భారం", "వాణిజ్య ఒప్పందం", "ఎగుమతులు", "దిగుమతులు",
      "మినహాయింపు",
    ],
  },
  // Tier 3b — major investments / industrial policy.
  {
    weight: 28,
    words: [
      "semiconductor", "chip fab", "chip plant", "solar plant",
      "hydrogen project", "data center", "data centre", "foreign direct investment",
      "billion investment", "mega factory", "gigafactory",
      "సెమీకండక్టర్", "పెట్టుబడులు", "సోలార్", "డేటా సెంటర్", "హైడ్రోజన్",
    ],
  },
  // Tier 3c — general economic shocks.
  {
    weight: 25,
    words: [
      "price hike", "layoffs", "job cuts", "budget", " rbi ", "fuel price",
      "bank collapse", "rate hike", "inflation surge", "stock crash",
      "ధరల పెంపు", "బడ్జెట్", "ఉద్యోగాల కోత", "ద్రవ్యోల్బణం",
    ],
  },
  // Tier 3d — mass public welfare schemes.
  {
    weight: 22,
    words: [
      "government scheme", "subsidy", "free health scheme", "salary hike",
      "pension increase", "minimum wage", "welfare scheme",
      "పథకం", "సబ్సిడీ", "జీతం పెంపు", "పింఛను", "సంక్షేమ",
    ],
  },
];
const NEGATIVE_WEIGHTS: Array<{ words: string[]; weight: number }> = [
  // PR/announcement verbs — the "CM's relief fund" problem.
  {
    weight: -25,
    words: [
      "inaugurates", "announces", "launches", "greets", "congratulates",
      "felicitates", "visits", "meets",
      "ప్రారంభించారు", "అభినందించారు", "పర్యటన", "సమావేశమయ్యారు", "శుభాకాంక్షలు",
    ],
  },
  // Listicle / evergreen content — never hero material.
  {
    weight: -30,
    words: [
      "tips for", "benefits of", "how to", "best ways", "things to know",
      "చిట్కాలు", "లాభాలు",
    ],
  },
];

function scoreHeadline(h: Headline): number {
  const hay = h.lang === "en" ? h.title.toLowerCase() : h.title;
  let score = 0;
  for (const { words, weight } of POSITIVE_WEIGHTS) {
    if (words.some((w) => hay.includes(w))) score += weight;
  }
  for (const { words, weight } of NEGATIVE_WEIGHTS) {
    if (words.some((w) => hay.includes(w))) score += weight;
  }
  // Recency: linear decay, +15 at 0h down to 0 at 12h+.
  const t = Date.parse(h.pubDate);
  if (!Number.isNaN(t)) {
    const hoursOld = (Date.now() - t) / 3_600_000;
    score += Math.max(0, 15 - (hoursOld / 12) * 15);
  }
  return score;
}

// English stopwords worth excluding from token-overlap comparisons (Telugu
// postpositions are attached, not separate tokens, so no Telugu stopword
// list is needed for this rough check).
const STOPWORDS = new Set([
  "the", "and", "for", "with", "that", "this", "from", "have", "will",
  "says", "said", "after", "over", "into", "amid", "amidst",
]);
function tokens(title: string): Set<string> {
  return new Set(
    title
      .toLowerCase()
      .split(/[^a-z0-9ఀ-౿]+/)
      .filter((w) => w.length > 3 && !STOPWORDS.has(w)),
  );
}

// Other headlines (different source) that share enough tokens with the pick
// to plausibly be independent coverage of the same event.
function corroborating(pick: Headline, pool: Headline[]): Headline[] {
  const pickTokens = tokens(pick.title);
  const out: Headline[] = [];
  for (const h of pool) {
    if (h === pick || h.source === pick.source) continue;
    const shared = [...tokens(h.title)].filter((t) => pickTokens.has(t));
    if (shared.length >= 2) out.push(h);
    if (out.length >= 3) break;
  }
  return out;
}

async function synthesize(
  facts: Headline[],
  geminiKey: string,
): Promise<{ title: string; commentary: string } | null> {
  const factLines = facts
    .map((h) => `- (${h.source}) ${h.title}`)
    .join("\n");
  const prompt =
    `You are a Telugu news editor writing an original explainer for a general ` +
    `audience. Below are headlines from independent news sources about the ` +
    `SAME story. Using ONLY the facts these headlines state — do not invent ` +
    `any number, name, or detail not present in them — write:\n` +
    `1. A short original Telugu headline (do not copy any source's exact wording).\n` +
    `2. A 3-4 sentence original Telugu explainer paragraph synthesizing the facts.\n` +
    `If the headlines don't give enough detail, keep the explainer brief and ` +
    `factual rather than padding it. Write in Telugu script only.\n\n` +
    `Headlines:\n${factLines}\n\n` +
    `Respond as JSON: {"title": "...", "commentary": "..."}`;
  const r = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${geminiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.6,
          maxOutputTokens: 500,
          responseMimeType: "application/json",
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
      signal: AbortSignal.timeout(40_000),
    },
  );
  if (!r.ok) return null;
  const data = await r.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  const text = (data.candidates?.[0]?.content?.parts ?? [])
    .map((p) => p.text ?? "").join("").trim();
  try {
    const parsed = JSON.parse(text) as { title?: string; commentary?: string };
    if (!parsed.title || !parsed.commentary) return null;
    return { title: parsed.title, commentary: parsed.commentary };
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY");
    if (!GEMINI_KEY) {
      return json({ error: "config_missing", message: "GEMINI_API_KEY" }, 500);
    }

    const [teResults, enResults] = await Promise.all([
      Promise.all(
        Object.keys(TE_TOPICS).map((t) => fetchGoogleNews(teFeedUrl(t), "te", 15)),
      ),
      Promise.all(EN_TOPIC_URLS.map((u) => fetchGoogleNews(u, "en", 20))),
    ]);
    const pool = [...teResults.flat(), ...enResults.flat()];
    if (pool.length === 0) {
      return json({ ok: true, available: false, reason: "no_candidates" });
    }

    const scored = pool
      .map((h) => ({ h, score: scoreHeadline(h) }))
      .sort((a, b) => b.score - a.score);
    const top = scored[0];
    const facts = [top.h, ...corroborating(top.h, pool)];

    const result = await synthesize(facts, GEMINI_KEY);
    if (!result) {
      return json({ ok: true, available: false, reason: "synthesis_failed" });
    }

    return json({
      ok: true,
      available: true,
      title: result.title,
      commentary: result.commentary,
      category: top.h.lang === "en" ? "international" : "national",
      sourceCount: facts.length,
      sources: facts.map((f) => f.source),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[feeds-explains]", err);
    return json({ error: "explains_failed", message }, 500);
  }
});
