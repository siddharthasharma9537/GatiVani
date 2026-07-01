import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// feeds-articles — aggregates publisher WordPress RSS feeds that carry the FULL
// article body in <content:encoded>. Unlike Google News (opaque redirect links,
// headline only), these feeds give the real publisher URL AND the whole story,
// so the app can render + narrate the article in-app with a single fetch.
//
// Server-side so the Flutter WEB app dodges CORS. Add publishers to FEEDS.

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
      "Cache-Control": "public, max-age=300",
    },
  });
}

// Publisher feeds that expose full <content:encoded>. Extend freely.
const FEEDS: Array<{ source: string; url: string }> = [
  { source: "NTV Telugu", url: "https://ntvtelugu.com/feed" },
  { source: "HMTV", url: "https://www.hmtvlive.com/feed" },
  { source: "Big TV", url: "https://www.bigtvlive.com/feed" },
];

const BODY_CAP = 9000; // chars — bound TTS cost + payload

function decodeEntities(s: string): string {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;|&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(parseInt(n, 10)))
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&");
}

function stripHtml(html: string): string {
  const noCdata = html.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1");
  const text = noCdata
    // Drop embed CONTAINERS whole — their inner text is foreign-language tweet
    // bodies, captions, iframe fallbacks etc. that would otherwise leak into the
    // article (and the narration). Must run before the generic tag strip.
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<blockquote[\s\S]*?<\/blockquote>/gi, " ") // X/Instagram embeds
    .replace(/<figure[\s\S]*?<\/figure>/gi, " ") // image + caption blocks
    .replace(/<iframe[\s\S]*?<\/iframe>/gi, " ") // video embeds
    .replace(/<\/(p|div|br|li|h\d)>/gi, "\n")
    .replace(/<[^>]+>/g, " ");
  return decodeEntities(text)
    // Belt-and-suspenders: nuke any stray tweet-embed remnants that sat outside
    // a blockquote (bare "pic.twitter.com/…" links, "— Handle (@x) date" lines).
    .replace(/pic\.twitter\.com\/\S+/gi, " ")
    // WordPress feed footer boilerplate, e.g. "The post <title> appeared first
    // on <Site>." — English junk that repeats the headline.
    .replace(/\s*The post [\s\S]*?appeared first on [^.\n]*\.?/gi, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]*\n[ \t]*/g, "\n")
    .trim();
}

function tag(block: string, name: string): string {
  const m = block.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)<\\/${name}>`));
  return m ? m[1] : "";
}

// Stable UUID (v5-shaped) from the article URL so TTS caching keys are valid
// uuid syntax and identical across sessions.
async function uuidFrom(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(s));
  const b = new Uint8Array(buf).slice(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${
    h.slice(16, 20)
  }-${h.slice(20)}`;
}

interface Article {
  id: string;
  title: string;
  link: string;
  source: string;
  pubDate: string;
  summary: string;
  body: string;
}

async function parseFeed(
  source: string,
  xml: string,
  perFeed: number,
): Promise<Article[]> {
  const out: Article[] = [];
  const re = /<item>([\s\S]*?)<\/item>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null && out.length < perFeed) {
    const block = m[1];
    const title = decodeEntities(tag(block, "title")).trim();
    const link = decodeEntities(tag(block, "link")).trim();
    if (!title || !link) continue;
    const encoded = tag(block, "content:encoded");
    const body = stripHtml(encoded).slice(0, BODY_CAP);
    if (body.length < 200) continue; // skip stubs with no real body
    const summary = stripHtml(tag(block, "description")).slice(0, 320);
    out.push({
      id: await uuidFrom(link),
      title,
      link,
      source,
      pubDate: tag(block, "pubDate").trim(),
      summary,
      body,
    });
  }
  return out;
}

async function fetchFeed(
  source: string,
  url: string,
  perFeed: number,
): Promise<Article[]> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 9000);
  try {
    const r = await fetch(url, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)" },
      signal: ctrl.signal,
    });
    if (!r.ok) return [];
    return await parseFeed(source, await r.text(), perFeed);
  } catch {
    return [];
  } finally {
    clearTimeout(t);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const url = new URL(req.url);
    let limit = parseInt(url.searchParams.get("limit") ?? "20", 10);
    if (req.method === "POST") {
      const b = await req.json().catch(() => ({})) as Record<string, unknown>;
      if (typeof b.limit === "number") limit = b.limit;
    }
    limit = Math.min(Math.max(Number.isFinite(limit) ? limit : 20, 1), 40);

    const perFeed = Math.ceil(limit / FEEDS.length) + 5;
    const results = await Promise.all(
      FEEDS.map((f) => fetchFeed(f.source, f.url, perFeed)),
    );
    const merged = results.flat();
    merged.sort((a, b) => {
      const ta = Date.parse(a.pubDate) || 0;
      const tb = Date.parse(b.pubDate) || 0;
      return tb - ta;
    });
    return json({ ok: true, count: merged.length, items: merged.slice(0, limit) });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[feeds-articles]", err);
    return json({ error: "feed_failed", message }, 500);
  }
});
