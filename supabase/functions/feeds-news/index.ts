import "jsr:@supabase/functions-js/edge-runtime.d.ts";

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

// Telugu, India locale.
const LOCALE = "hl=te&gl=IN&ceid=IN:te";

// topic → Google News search query (Telugu). "top" uses the headlines feed.
const TOPICS: Record<string, string> = {
  top: "",
  politics: "రాజకీయాలు",
  cricket: "క్రికెట్",
  cinema: "సినిమా టాలీవుడ్",
  weather: "వాతావరణం ఆంధ్రప్రదేశ్ తెలంగాణ",
  national: "భారతదేశం",
  business: "వ్యాపారం స్టాక్ మార్కెట్",
};

function feedUrl(topic: string): string {
  const base = "https://news.google.com/rss";
  const q = TOPICS[topic];
  if (!q) return `${base}?${LOCALE}`; // top headlines
  return `${base}/search?q=${encodeURIComponent(q)}&${LOCALE}`;
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
    let limit = parseInt(url.searchParams.get("limit") ?? "12", 10);
    if (req.method === "POST") {
      const b = await req.json().catch(() => ({})) as Record<string, unknown>;
      if (typeof b.topic === "string") topic = b.topic;
      if (typeof b.limit === "number") limit = b.limit;
    }
    if (!(topic in TOPICS)) topic = "top";
    limit = Math.min(Math.max(Number.isFinite(limit) ? limit : 12, 1), 30);

    const resp = await fetch(feedUrl(topic), {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)" },
    });
    if (!resp.ok) {
      return json({ error: "upstream_error", status: resp.status }, 502);
    }
    const xml = await resp.text();
    const items = parseItems(xml, limit);
    return json({ ok: true, topic, count: items.length, items });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[feeds-news]", err);
    return json({ error: "feed_failed", message }, 500);
  }
});
