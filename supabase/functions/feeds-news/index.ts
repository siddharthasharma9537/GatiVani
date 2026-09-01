import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

// feeds-news — server-side fetch + parse of Google News' Telugu RSS.
//
// Why an edge function: the app is Flutter WEB, so a browser-side fetch of
// news.google.com is blocked by CORS. This function fetches the feed
// server-side (no CORS), normalises it to JSON, and the app renders it in the
// Live screen's marquee + Latest stories. No TTS, no cost — these are text
// headlines linking back to the publisher.

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
      // Edge-cache the feed for 5 min so we don't hammer Google News and the
      // app gets a fast response.
      "Cache-Control": "public, max-age=300",
    },
  });
}

// News Language: per-language Google News locale + topic query strings.
// "top" uses the plain headlines feed (no search query).
const LOCALES: Record<string, string> = {
  te: "hl=te&gl=IN&ceid=IN:te",
  hi: "hl=hi&gl=IN&ceid=IN:hi",
};
const TOPICS: Record<string, Record<string, string>> = {
  te: {
    top: "",
    politics: "రాజకీయాలు",
    cricket: "క్రికెట్",
    cinema: "సినిమా టాలీవుడ్",
    weather: "వాతావరణం ఆంధ్రప్రదేశ్ తెలంగాణ",
    national: "భారతదేశం",
    business: "వ్యాపారం స్టాక్ మార్కెట్",
  },
  hi: {
    top: "",
    politics: "राजनीति",
    cricket: "क्रिकेट",
    cinema: "बॉलीवुड सिनेमा",
    weather: "मौसम भारत",
    national: "भारत",
    business: "व्यापार शेयर बाजार",
  },
};

// Google News throttles this function's IP range: ~40% of requests come back
// 503 after a ~10s hang, while the same request from a residential IP is a
// 0.25s 200. So: fail fast, retry once, and fall back to the last good payload
// rather than showing an empty feed. See the feed_cache migration.
const FETCH_TIMEOUT_MS = 4000;
const CACHE_FRESH_MS = 5 * 60 * 1000;

const supabase = (() => {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  return url && key ? createClient(url, key) : null;
})();

async function readCache(cacheKey: string) {
  if (!supabase) return null;
  const { data, error } = await supabase
    .from("feed_cache").select("payload, fetched_at")
    .eq("source", "news").eq("cache_key", cacheKey).maybeSingle();
  if (error) {
    console.warn("[feeds-news] cache read failed:", error.message);
    return null;
  }
  return data ?? null;
}

async function writeCache(cacheKey: string, payload: unknown) {
  if (!supabase) return;
  const { error } = await supabase.from("feed_cache").upsert({
    source: "news",
    cache_key: cacheKey,
    payload,
    fetched_at: new Date().toISOString(),
  }, { onConflict: "source,cache_key" });
  if (error) console.warn("[feeds-news] cache write failed:", error.message);
}

/** One attempt at the upstream feed, bounded by FETCH_TIMEOUT_MS. */
async function fetchFeedOnce(url: string): Promise<string> {
  const resp = await fetch(url, {
    headers: { "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)" },
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  if (!resp.ok) throw new Error(`upstream ${resp.status}`);
  return await resp.text();
}

/** Two attempts with a short backoff — most 503s here are transient throttling,
 *  so a single retry converts the majority of them into successes. */
async function fetchFeed(url: string): Promise<string> {
  try {
    return await fetchFeedOnce(url);
  } catch (first) {
    console.warn("[feeds-news] attempt 1 failed:", first);
    await new Promise((r) => setTimeout(r, 300));
    return await fetchFeedOnce(url);
  }
}

function feedUrl(lang: string, topic: string): string {
  const base = "https://news.google.com/rss";
  const locale = LOCALES[lang] ?? LOCALES.te;
  const q = (TOPICS[lang] ?? TOPICS.te)[topic];
  if (!q) return `${base}?${locale}`; // top headlines
  return `${base}/search?q=${encodeURIComponent(q)}&${locale}`;
}

// Minimal HTML/XML entity decode for the fields we surface.
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

interface NewsItem {
  title: string;
  link: string;
  source: string;
  pubDate: string;
}

function parseItems(xml: string, limit: number): NewsItem[] {
  const items: NewsItem[] = [];
  const re = /<item>([\s\S]*?)<\/item>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null && items.length < limit) {
    const block = m[1];
    const source = pick(block, "source");
    let title = pick(block, "title");
    // Google News titles read "Headline - Source"; drop the trailing source.
    if (source && title.endsWith(` - ${source}`)) {
      title = title.slice(0, -(source.length + 3)).trim();
    }
    const link = pick(block, "link");
    if (!title || !link) continue;
    items.push({ title, link, source, pubDate: pick(block, "pubDate") });
  }
  return items;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const url = new URL(req.url);
    let topic = url.searchParams.get("topic") ?? "top";
    let lang = url.searchParams.get("lang") ?? "te";
    let limit = parseInt(url.searchParams.get("limit") ?? "12", 10);
    if (req.method === "POST") {
      const b = await req.json().catch(() => ({})) as Record<string, unknown>;
      if (typeof b.topic === "string") topic = b.topic;
      if (typeof b.lang === "string") lang = b.lang;
      if (typeof b.limit === "number") limit = b.limit;
    }
    if (!(lang in TOPICS)) lang = "te";
    if (!(topic in TOPICS[lang])) topic = "top";
    limit = Math.min(Math.max(Number.isFinite(limit) ? limit : 12, 1), 30);

    // `limit` only trims the parsed list, so it is deliberately not part of the
    // cache key — one stored payload serves every limit for a lang+topic.
    const cacheKey = `${lang}:${topic}`;
    const cached = await readCache(cacheKey);

    if (cached && Date.now() - new Date(cached.fetched_at).getTime() < CACHE_FRESH_MS) {
      const items = (cached.payload as { items: unknown[] }).items ?? [];
      return json({
        ok: true, topic, lang,
        count: Math.min(items.length, limit),
        items: items.slice(0, limit),
        cached: true,
      });
    }

    try {
      const xml = await fetchFeed(feedUrl(lang, topic));
      const items = parseItems(xml, 30); // cache the full set, trim per request
      await writeCache(cacheKey, { items });
      return json({
        ok: true, topic, lang,
        count: Math.min(items.length, limit),
        items: items.slice(0, limit),
      });
    } catch (fetchErr) {
      // Upstream is throttling us. Stale headlines beat an empty screen, so
      // serve the last good payload however old it is; only a cold cache is a
      // real failure.
      console.warn("[feeds-news] upstream failed, falling back to cache:", fetchErr);
      if (cached) {
        const items = (cached.payload as { items: unknown[] }).items ?? [];
        return json({
          ok: true, topic, lang,
          count: Math.min(items.length, limit),
          items: items.slice(0, limit),
          cached: true,
          stale: true,
          fetchedAt: cached.fetched_at,
        });
      }
      return json({
        error: "upstream_error",
        message: fetchErr instanceof Error ? fetchErr.message : "fetch failed",
      }, 502);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[feeds-news]", err);
    return json({ error: "feed_failed", message }, 500);
  }
});
