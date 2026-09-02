import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

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
//
// Candidates below were verified live (not from stale notes) before adding:
// fetched each feed, confirmed 200 + real <item>/<content:encoded> XML (not an
// HTML/SPA fallback), confirmed pubDate is actually current, and confirmed
// content:encoded bodies are substantial (~1-6k chars, not stub summaries).
// Rejected candidates and why: eenadu.net, sakshi.com, andhrajyothy.com,
// andhraprabha.com, teluguone.com, apherald.com — no real RSS endpoint found
// (redirect to HTML/SPA or 404); telugu.oneindia.com, etvbharat.com — feed
// exists but has no content:encoded (headline/summary only, fails the
// full-body requirement this endpoint exists for); tv5news.in — real feed but
// frozen (newest item was 5+ weeks stale, so it was dropped for freshness).
// 10tv.in/feed passes all of the above from a plain client but silently
// returns nothing when fetched from here — blocked at the network level for
// Supabase's edge IPs (same class of block CricAPI had). Can't route around
// it client-side like CricAPI/Cricbuzz either: its CORS header locks
// Access-Control-Allow-Origin to https://10tv.in itself, not permissive.
// Dropped rather than building a proxy for one source.
const FEEDS_TE: Array<{ source: string; url: string }> = [
  { source: "NTV Telugu", url: "https://ntvtelugu.com/feed" },
  { source: "HMTV", url: "https://www.hmtvlive.com/feed" },
  { source: "Big TV", url: "https://www.bigtvlive.com/feed" },
  { source: "TV9 Telugu", url: "https://tv9telugu.com/feed" },
  { source: "V6 News", url: "https://www.v6velugu.com/feed" },
  { source: "NT News", url: "https://www.ntnews.com/feed" },
  { source: "Telugu360", url: "https://www.telugu360.com/feed" },
  { source: "Mana Telangana", url: "https://www.manatelangana.news/feed" },
];

// Hindi publishers — verified live the same way as the Telugu list above:
// fetched, confirmed real <content:encoded> bodies (not stub summaries),
// confirmed current pubDate, confirmed genuinely Hindi (not an
// English-language feed mislabeled under a Hindi-sounding domain — several
// candidates failed exactly that check and were dropped: news24online.com
// (English despite the name), NDTV Khabar (content:encoded present but only
// ~180 chars, a teaser not a body), Navbharat Times/Jagran/Zee/News18/Patrika
// (no working RSS or no content:encoded found).
const FEEDS_HI: Array<{ source: string; url: string }> = [
  { source: "Prabhat Khabar", url: "https://www.prabhatkhabar.com/feed" },
  { source: "TV9 Hindi", url: "https://www.tv9hindi.com/feed" },
  { source: "Desh Bandhu", url: "https://www.deshbandhu.co.in/feed" },
  { source: "Samachar Jagat", url: "https://www.samacharjagat.com/feed" },
];

const FEEDS_BY_LANG: Record<string, Array<{ source: string; url: string }>> = {
  te: FEEDS_TE,
  hi: FEEDS_HI,
};

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
  const noCdata = html
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    // Some feeds ship literal CRLF line breaks in the body text itself (not
    // <p>/<br> tags), which the \n{3,} blank-line collapse below never sees
    // because it only matches bare \n runs — normalize before anything else.
    .replace(/\r\n?/g, "\n");
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

// Some feeds repeat the headline as the article body's own first line —
// harmless visually (easy to skim past) but narrated aloud it plays as the
// story announcing its own title twice in a row. Strip it when the first
// paragraph is (near-)identical to the title.
function stripLeadingDupeTitle(body: string, title: string): string {
  const normalize = (s: string) =>
    s.trim().replace(/[.!?…]+$/g, "").replace(/\s+/g, " ").toLowerCase();
  const nTitle = normalize(title);
  if (!nTitle) return body;
  const firstBreak = body.indexOf("\n");
  const firstPara = (firstBreak === -1 ? body : body.slice(0, firstBreak));
  if (normalize(firstPara) === nTitle) {
    return firstBreak === -1 ? "" : body.slice(firstBreak).trimStart();
  }
  return body;
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
    const body = stripLeadingDupeTitle(
      stripHtml(encoded).slice(0, BODY_CAP),
      title,
    );
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
    if (!r.ok) {
      console.warn(`[feeds-articles] ${source} HTTP ${r.status}`);
      return [];
    }
    return await parseFeed(source, await r.text(), perFeed);
  } catch (e) {
    console.warn(`[feeds-articles] ${source} failed:`, (e as Error).message);
    return [];
  } finally {
    clearTimeout(t);
  }
}

// The published pre-synthesized batch for this language, if there is one.
//
// feeds-warm stages a batch, narrates every article in it out of band, and only
// then marks it published — so everything in here is guaranteed to have its
// audio already cached, and playback never waits on Gemini. Falling back to the
// live fetch when no batch exists keeps this endpoint working exactly as it did
// before warming existed (first deploy, a language nobody warms, warming off).
const supabase = (() => {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  return url && key ? createClient(url, key) : null;
})();

async function publishedBatch(lang: string): Promise<Article[] | null> {
  if (!supabase) return null;
  const { data, error } = await supabase
    .from("live_batches").select("items")
    .eq("lang", lang).eq("status", "published")
    .order("published_at", { ascending: false }).limit(1).maybeSingle();
  if (error) {
    console.warn("[feeds-articles] batch read failed:", error.message);
    return null;
  }
  const items = data?.items;
  return Array.isArray(items) && items.length ? items as Article[] : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const url = new URL(req.url);
    let limit = parseInt(url.searchParams.get("limit") ?? "20", 10);
    let lang = url.searchParams.get("lang") ?? "te";
    // `raw` bypasses the published batch and forces the live publisher fetch.
    // feeds-warm needs it to build the NEXT batch — without it the warm job
    // would re-stage the batch it just published, forever.
    let raw = url.searchParams.get("raw") === "1";
    if (req.method === "POST") {
      const b = await req.json().catch(() => ({})) as Record<string, unknown>;
      if (typeof b.limit === "number") limit = b.limit;
      if (typeof b.lang === "string") lang = b.lang;
      if (b.raw === true) raw = true;
    }
    limit = Math.min(Math.max(Number.isFinite(limit) ? limit : 20, 1), 40);

    if (!raw) {
      const batch = await publishedBatch(lang);
      if (batch) {
        return json({
          ok: true,
          count: batch.length,
          items: batch.slice(0, limit),
          source: "batch",
        });
      }
    }
    const feeds = FEEDS_BY_LANG[lang] ?? FEEDS_TE;

    const perFeed = Math.ceil(limit / feeds.length) + 5;
    const results = await Promise.all(
      feeds.map((f) => fetchFeed(f.source, f.url, perFeed)),
    );
    const merged = results.flat();
    merged.sort((a, b) => {
      const ta = Date.parse(a.pubDate) || 0;
      const tb = Date.parse(b.pubDate) || 0;
      return tb - ta;
    });
    return json({ ok: true, count: merged.length, items: merged.slice(0, limit), source: "live" });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[feeds-articles]", err);
    return json({ error: "feed_failed", message }, 500);
  }
});
