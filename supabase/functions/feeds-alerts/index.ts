import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// feeds-alerts — personal notification watch: exam results, admit cards and
// government job notifications, per user-chosen topic.
//
// Same server-side Google News RSS mechanism as feeds-news (browser fetch of
// news.google.com is CORS-blocked, so the edge function does it). For each
// requested topic we run a *release-shaped* search — the exam/board name AND
// announcement words (result, declared, admit card, notification, …) — then
// post-filter titles against RELEASE_RE so a random opinion piece that
// mentions "JEE" doesn't page anyone. Headlines link back to the publisher;
// nothing is reproduced.
//
// GET ?topics=jee,neet,upsc[&limit=8]  → { ok, items: [{topic, title, link,
//                                          source, pubDate}] } newest first.
// Topic ids mirror the app's kAlertTopics (packages/app/lib/config/
// alert_topics.dart) — keep the two lists in sync.

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
      // Agencies publish a handful of times a day at most; 10 min edge cache
      // keeps the poll cheap without making "as soon as released" a lie.
      "Cache-Control": "public, max-age=600",
    },
  });
}

// The announcement vocabulary — English + Telugu. A headline must hit one of
// these to count as an alert rather than ordinary coverage.
const RELEASE_RE = new RegExp(
  [
    "result", "results", "declared", "released", "announce", "announced",
    "admit card", "hall ticket", "notification", "notified", "schedule",
    "time ?table", "date sheet", "exam date", "answer key", "counselling",
    "counseling", "cut ?off", "merit list", "rank card", "score ?card",
    "registration", "apply", "application", "vacanc", "recruitment",
    "ఫలితాలు", "విడుదల", "ప్రకటించ", "ప్రకటన", "నోటిఫికేషన్", "హాల్ టికెట్",
    "అడ్మిట్ కార్డ్", "షెడ్యూల్", "దరఖాస్తు", "నియామక", "ఖాళీలు", "కౌన్సెలింగ్",
    "ఆన్సర్ కీ", "ర్యాంక్",
  ].join("|"),
  "i",
);

// topic id → the search each runs on Google News. `en`/`te` pick the edition;
// most agencies are covered in English media first, Telugu terms catch the
// state-board/TSPSC/APPSC stories that never make English feeds.
interface TopicSpec {
  en?: string;
  te?: string;
}
const TOPICS: Record<string, TopicSpec> = {
  jee: {
    en: '"JEE Main" OR "JEE Advanced" (result OR "admit card" OR notification OR "exam date" OR "answer key")',
  },
  neet: {
    en: '"NEET UG" OR "NEET PG" OR NEET (result OR "admit card" OR counselling OR notification OR "answer key")',
  },
  eapcet: {
    en: '"EAPCET" OR "EAMCET" (result OR "hall ticket" OR counselling OR notification OR "rank card")',
    te: "ఎంసెట్ OR ఈఏపీసెట్",
  },
  cat: {
    en: '"CAT exam" OR "IIM CAT" (result OR registration OR "admit card" OR notification OR "score card")',
  },
  gate: {
    en: '"GATE exam" OR "GATE 2026" OR "GATE 2027" (result OR "admit card" OR registration OR "answer key" OR scorecard)',
  },
  boards: {
    en: '"SSC results" OR "Intermediate results" OR "CBSE" OR "board exam" (Telangana OR "Andhra Pradesh" OR CBSE) (result OR "time table" OR "hall ticket" OR supplementary)',
    te: "పదో తరగతి OR ఇంటర్ పరీక్షలు ఫలితాలు",
  },
  upsc: {
    en: 'UPSC "civil services" OR UPSC (result OR notification OR "admit card" OR interview OR "exam date" OR vacancy)',
  },
  tspsc: {
    en: 'TSPSC (notification OR result OR "hall ticket" OR recruitment OR vacancy)',
    te: "టీఎస్పీఎస్సీ",
  },
  appsc: {
    en: 'APPSC (notification OR result OR "hall ticket" OR recruitment OR vacancy)',
    te: "ఏపీపీఎస్సీ",
  },
  ssc_jobs: {
    en: '"Staff Selection Commission" OR "SSC CGL" OR "SSC CHSL" OR "SSC GD" (notification OR result OR "admit card" OR vacancy OR recruitment)',
  },
  railways: {
    en: '"RRB" OR "railway recruitment" (notification OR result OR "admit card" OR vacancy OR "exam date")',
  },
  banking: {
    en: '"IBPS" OR "SBI PO" OR "SBI Clerk" OR "bank recruitment" (notification OR result OR "admit card" OR vacancy)',
  },
  dsc: {
    en: '"DSC recruitment" OR "TET" (Telangana OR "Andhra Pradesh") (notification OR result OR "hall ticket" OR vacancy)',
    te: "డీఎస్సీ OR టెట్ నోటిఫికేషన్",
  },
};

function feedUrl(q: string, lang: "en" | "te"): string {
  const locale = lang === "te"
    ? "hl=te&gl=IN&ceid=IN:te"
    : "hl=en-IN&gl=IN&ceid=IN:en";
  return `https://news.google.com/rss/search?q=${encodeURIComponent(q)}&${locale}`;
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

interface AlertItem {
  topic: string;
  title: string;
  link: string;
  source: string;
  pubDate: string;
}

function parseItems(xml: string, topic: string, limit: number): AlertItem[] {
  const items: AlertItem[] = [];
  const re = /<item>([\s\S]*?)<\/item>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null && items.length < limit) {
    const block = m[1];
    const source = pick(block, "source");
    let title = pick(block, "title");
    if (source && title.endsWith(` - ${source}`)) {
      title = title.slice(0, -(source.length + 3)).trim();
    }
    const link = pick(block, "link");
    if (!title || !link) continue;
    if (!RELEASE_RE.test(title)) continue; // announcements only
    items.push({ topic, title, link, source, pubDate: pick(block, "pubDate") });
  }
  return items;
}

async function fetchTopic(topic: string, limit: number): Promise<AlertItem[]> {
  const spec = TOPICS[topic];
  if (!spec) return [];
  const feeds: Array<["en" | "te", string]> = [];
  if (spec.en) feeds.push(["en", spec.en]);
  if (spec.te) feeds.push(["te", spec.te]);
  const results = await Promise.all(feeds.map(async ([lang, q]) => {
    try {
      const resp = await fetch(feedUrl(q, lang), {
        headers: { "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)" },
      });
      if (!resp.ok) return [];
      return parseItems(await resp.text(), topic, limit);
    } catch {
      return [];
    }
  }));
  return results.flat();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const url = new URL(req.url);
    let topicsParam = url.searchParams.get("topics") ?? "";
    let limit = parseInt(url.searchParams.get("limit") ?? "8", 10);
    if (req.method === "POST") {
      const b = await req.json().catch(() => ({})) as Record<string, unknown>;
      if (typeof b.topics === "string") topicsParam = b.topics;
      if (typeof b.limit === "number") limit = b.limit;
    }
    limit = Math.min(Math.max(Number.isFinite(limit) ? limit : 8, 1), 20);

    const topics = topicsParam
      .split(",")
      .map((t) => t.trim())
      .filter((t) => t in TOPICS);
    if (topics.length === 0) {
      return json({ ok: true, topics: [], count: 0, items: [] });
    }

    const perTopic = await Promise.all(
      topics.map((t) => fetchTopic(t, limit)),
    );

    // Merge, dedupe (the same PIB headline surfaces under several topics),
    // newest first.
    const seen = new Set<string>();
    const items = perTopic.flat().filter((it) => {
      const key = it.title.toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    }).sort((a, b) =>
      new Date(b.pubDate).getTime() - new Date(a.pubDate).getTime()
    );

    return json({ ok: true, topics, count: items.length, items });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
