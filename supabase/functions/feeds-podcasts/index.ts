import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// feeds-podcasts — real Telugu podcast episodes for the Podcasts grid. Each
// show is fetched from its own public RSS feed (found via Apple's keyless
// iTunes Search API and verified by hand — active, legitimate, independent
// productions, not rebroadcasts of copyrighted broadcast content). We surface
// the latest episode's title + direct MP3 enclosure; the app plays it
// straight through the shared player (PlaybackService skips TTS entirely
// once NewspaperArticle.audioUrl is already a real http URL).
//
// Server-side so the Flutter WEB app dodges CORS.

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
      "Cache-Control": "public, max-age=1800",
    },
  });
}

interface Show {
  key: string;
  title: string;
  url: string;
}

// Only shows with a real, reachable, legitimately-produced RSS feed. Add more
// once verified the same way (fetch the feed, confirm recent episodes and a
// working enclosure URL).
const SHOWS: Show[] = [
  {
    key: "bhagavad_gita",
    title: "Bhagavad Gita",
    url: "https://feeds.redcircle.com/d01d2370-a9fb-4c6c-ab53-4ec14800e9b7",
  },
  {
    key: "cinema_talk",
    title: "Cinema Talk",
    url: "https://kottavibe.com/podcast.xml",
  },
];

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

function tag(block: string, name: string): string {
  const m = block.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)<\\/${name}>`));
  return m ? m[1] : "";
}

// "822" (seconds) or "13:42" / "1:02:15" — feeds use either.
function parseDuration(raw: string): number {
  const s = raw.trim();
  if (!s) return 0;
  if (/^\d+$/.test(s)) return parseInt(s, 10);
  const parts = s.split(":").map((p) => parseInt(p, 10));
  if (parts.some((p) => Number.isNaN(p))) return 0;
  return parts.reduce((acc, p) => acc * 60 + p, 0);
}

interface Episode {
  key: string;
  title: string; // show name
  episodeTitle: string;
  audioUrl: string;
  durationSeconds: number;
  pubDate: string;
}

async function fetchShow(show: Show): Promise<Episode | null> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 9000);
  try {
    const r = await fetch(show.url, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)" },
      signal: ctrl.signal,
    });
    if (!r.ok) return null;
    const xml = await r.text();
    const m = /<item>([\s\S]*?)<\/item>/.exec(xml);
    if (!m) return null;
    const block = m[1];
    const episodeTitle = decodeEntities(tag(block, "title")).trim();
    // Attribute order varies by host (RedCircle puts url last, others first) —
    // match url="..." anywhere inside the tag rather than assuming a position.
    const encMatch = block.match(/<enclosure[^>]*\burl="([^"]+)"/);
    const audioUrl = encMatch ? decodeEntities(encMatch[1]) : "";
    if (!episodeTitle || !audioUrl) return null;
    return {
      key: show.key,
      title: show.title,
      episodeTitle,
      audioUrl,
      durationSeconds: parseDuration(tag(block, "itunes:duration")),
      pubDate: decodeEntities(tag(block, "pubDate")).trim(),
    };
  } catch {
    return null;
  } finally {
    clearTimeout(t);
  }
}

// AIR Telugu News — the latest bulletin, scraped from Prasar Bharati's own
// bulletin archive page. This is official AIR content on their own domain
// (not a rebroadcast); it just isn't exposed through their WordPress REST API
// or any RSS feed, so a light HTML parse of the rendered listing is the only
// way to reach it. The host returns 403 for HEAD requests (an anti-scraping
// rule) but serves GET fine — every fetch here must use GET.
const AIR_TELUGU_URL = "https://newsonair.gov.in/bulletins-city/telugu/";
const AIR_ASSUMED_BITRATE_BPS = 56_000; // consistent across observed bulletins

async function fetchAirTelugu(): Promise<Episode | null> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 12000);
  try {
    const r = await fetch(AIR_TELUGU_URL, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)" },
      signal: ctrl.signal,
    });
    if (!r.ok) return null;
    const html = await r.text();
    // Bulletins are listed newest-first; take the first box's fields.
    const block = (html.split('<div class="bulletinBox">')[1] ?? "").slice(
      0,
      3000,
    );
    const hrefMatch = block.match(/href="([^"]+\.mp3)"/);
    // The bare domain's WAF resets in-browser <audio> fetches (works fine
    // server-side, but the browser gets net::ERR_EMPTY_RESPONSE); the "www."
    // host serves the identical file — try it in case it sits behind a less
    // aggressive rule set.
    const audioUrl = hrefMatch
      ? hrefMatch[1].replace("https://newsonair.gov.in/", "https://www.newsonair.gov.in/")
      : "";
    if (!audioUrl) return null;
    // The title block's markup is malformed (opens <h3>, closes </h4>) — accept
    // either. Its last non-empty line is the bulletin time, e.g. "2030".
    const titleBlock = block.match(/<h3 class="title">([\s\S]*?)<\/h[34]>/);
    const lines = titleBlock
      ? titleBlock[1]
        .split("\n")
        .map((l) => l.replace(/<[^>]+>/g, "").trim())
        .filter(Boolean)
      : [];
    const time = lines[lines.length - 1] ?? "";
    const dateMatch = block.match(/<p>([^<]+)<\/p>/);
    const dateStr = dateMatch ? dateMatch[1].trim() : ""; // "01 Jul 2026"
    if (time.length !== 4 || !dateStr) return null;
    const hh = time.slice(0, 2), mm = time.slice(2, 4);
    // Matches the app's RFC822-ish parser: "DD Mon YYYY HH:MM:SS".
    const pubDate = `${dateStr} ${hh}:${mm}:00 +0000`;
    // Cheap duration estimate via a 1-byte range request (HEAD is blocked) —
    // avoids downloading the whole multi-MB bulletin just to size it.
    let durationSeconds = 0;
    try {
      const rr = await fetch(audioUrl, {
        headers: {
          "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)",
          "Range": "bytes=0-1",
        },
        signal: ctrl.signal,
      });
      const range = rr.headers.get("content-range"); // "bytes 0-1/4092108"
      const total = range ? parseInt(range.split("/")[1] ?? "0", 10) : 0;
      if (total > 0) {
        durationSeconds = Math.round((total * 8) / AIR_ASSUMED_BITRATE_BPS);
      }
    } catch {
      // best-effort — a missing duration just shows as unknown in the UI
    }
    return {
      key: "air_news",
      title: "AIR Telugu News",
      episodeTitle: `AIR Telugu News — ${hh}:${mm}`,
      audioUrl,
      durationSeconds,
      pubDate,
    };
  } catch {
    return null;
  } finally {
    clearTimeout(t);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const results = await Promise.all([
      ...SHOWS.map(fetchShow),
      fetchAirTelugu(),
    ]);
    const items = results.filter((x): x is Episode => x !== null);
    return json({ ok: true, items });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[feeds-podcasts]", err);
    return json({ error: "podcasts_failed", message }, 500);
  }
});
