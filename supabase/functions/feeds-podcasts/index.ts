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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const results = await Promise.all(SHOWS.map(fetchShow));
    const items = results.filter((x): x is Episode => x !== null);
    return json({ ok: true, items });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[feeds-podcasts]", err);
    return json({ error: "podcasts_failed", message }, 500);
  }
});
