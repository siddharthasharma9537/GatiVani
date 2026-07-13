import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

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
    // newsonair's WAF black-holes in-browser <audio> fetches entirely, and
    // even server-side fetches get TLS-reset intermittently — so streaming
    // per-listen (direct OR proxied) is a coin flip. Instead each bulletin is
    // copied ONCE into the public "audio" bucket and served from Supabase's
    // CDN. The copy runs in the background (waitUntil) so this feed response
    // never waits on the flaky host; until it lands, the audioUrl falls back
    // to the mkb-audio-proxy stream, which works most of the time.
    const storagePath = `air/${dateStr.replace(/\s+/g, "-")}-${hh}${mm}.mp3`;
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabase = (SUPABASE_URL && SERVICE_KEY)
      ? createClient(SUPABASE_URL, SERVICE_KEY)
      : null;

    let servedUrl = `${MKB_PROXY_URL}?src=${encodeURIComponent(audioUrl)}`;
    let durationSeconds = 0;
    let cached = false;
    if (supabase) {
      const publicUrl =
        supabase.storage.from("audio").getPublicUrl(storagePath).data.publicUrl;
      try {
        const head = await fetch(publicUrl, {
          method: "HEAD",
          signal: ctrl.signal,
        });
        if (head.ok) {
          cached = true;
          servedUrl = publicUrl;
          const size = parseInt(head.headers.get("content-length") ?? "0", 10);
          if (size > 0) {
            durationSeconds = Math.round((size * 8) / AIR_ASSUMED_BITRATE_BPS);
          }
        }
      } catch {
        // storage HEAD failed — keep the proxy fallback
      }
      if (!cached) {
        EdgeRuntime.waitUntil((async () => {
          for (let attempt = 0; attempt < 3; attempt++) {
            try {
              const dl = new AbortController();
              const dt = setTimeout(() => dl.abort(), 60_000);
              // "Range: bytes=0-" — a bare GET (no Range) gets TLS-reset far
              // more often; asking for an explicit whole-file range passes.
              const res = await fetch(audioUrl, {
                headers: {
                  "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)",
                  "Range": "bytes=0-",
                },
                signal: dl.signal,
              });
              if (res.status !== 200 && res.status !== 206) {
                throw new Error(`upstream ${res.status}`);
              }
              const bytes = new Uint8Array(await res.arrayBuffer());
              clearTimeout(dt);
              if (bytes.length < 100_000) throw new Error("suspiciously small");
              const { error } = await supabase.storage
                .from("audio")
                .upload(storagePath, bytes, {
                  contentType: "audio/mpeg",
                  upsert: true,
                });
              if (error) throw error;
              console.log(`[feeds-podcasts] cached AIR bulletin ${storagePath} (${bytes.length}b)`);
              return;
            } catch (e) {
              console.warn(`[feeds-podcasts] AIR cache attempt ${attempt + 1} failed:`, e);
            }
          }
        })());
      }
    }
    if (durationSeconds === 0) {
      // Cheap size probe for the duration estimate (HEAD is blocked upstream).
      try {
        const rr = await fetch(audioUrl, {
          headers: {
            "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)",
            "Range": "bytes=0-1",
          },
          signal: ctrl.signal,
        });
        const range = rr.headers.get("content-range"); // "bytes 0-1/4092108"
        let total = range ? parseInt(range.split("/")[1] ?? "0", 10) : 0;
        // The WAF sometimes ignores Range and answers 200 with the full
        // file — its content-length is the same total we wanted.
        if (total <= 0 && rr.status === 200) {
          total = parseInt(rr.headers.get("content-length") ?? "0", 10);
        }
        try {
          await rr.body?.cancel(); // never actually download the bulletin here
        } catch { /* already closed */ }
        if (total > 0) {
          durationSeconds = Math.round((total * 8) / AIR_ASSUMED_BITRATE_BPS);
        }
      } catch {
        // best-effort — a missing duration just shows as unknown in the UI
      }
    }
    return {
      key: "air_news",
      title: "AIR Telugu News",
      episodeTitle: `AIR Telugu News — ${hh}:${mm}`,
      audioUrl: servedUrl,
      durationSeconds,
      pubDate,
    };
  } catch {
    return null;
  } finally {
    clearTimeout(t);
  }
}

// When the live scrape fails (the WAF flakes on the listing page too), fall
// back to the NEWEST bulletin already cached in storage — a few hours stale
// beats the tile silently vanishing from the feed.
async function airFromStorage(): Promise<Episode | null> {
  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SERVICE_KEY) return null;
  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data, error } = await supabase.storage.from("audio").list("air", {
      limit: 1,
      sortBy: { column: "created_at", order: "desc" },
    });
    if (error || !data?.length) return null;
    const f = data[0]; // name like "11-Jul-2026-0705.mp3"
    const m = f.name.match(/^(\d{2})-([A-Za-z]{3})-(\d{4})-(\d{2})(\d{2})\.mp3$/);
    const size = (f.metadata as { size?: number } | null)?.size ?? 0;
    return {
      key: "air_news",
      title: "AIR Telugu News",
      episodeTitle: m
        ? `AIR Telugu News — ${m[4]}:${m[5]}`
        : "AIR Telugu News",
      audioUrl:
        supabase.storage.from("audio").getPublicUrl(`air/${f.name}`).data
          .publicUrl,
      durationSeconds:
        size > 0 ? Math.round((size * 8) / AIR_ASSUMED_BITRATE_BPS) : 0,
      pubDate: m ? `${m[1]} ${m[2]} ${m[3]} ${m[4]}:${m[5]}:00 +0000` : "",
    };
  } catch {
    return null;
  }
}

// Mann Ki Baat — PM Modi's monthly radio address, scraped from the official
// PMO archive (pmonradio.nic.in). The site has no RSS/API: each episode's
// audio is loaded via a legacy AJAX call — the homepage's <body onload>
// names the LATEST episode's div id, and hideallexcept() (see
// js/image_slide.js) base64-encodes that id and POSTs it to pcvideocode.asp,
// which returns an <iframe> whose hlsurl query param is the real MP3.
// Hindi only — checked pmonradio.nic.in itself (no language switcher at all)
// and AIR's regional-language archive (rnu-nsd-audio-archive-search lists
// Assamese, Bengali, Dogri, Gujarati, Hindi, Marathi, Rajasthani, Urdu; no
// Telugu) — no Telugu version is reachable through any official channel.
//
// The CDN (playhls.media.nic.in) 403s unless the request's Referer is
// pmonradio.nic.in itself, which a browser <audio> element can never send on
// its own — so the audioUrl below points at mkb-audio-proxy, not the raw CDN
// link, unlike every other source in this file.
const PMO_RADIO_URL = "https://pmonradio.nic.in/";
const MKB_MONTHS: Record<string, string> = {
  january: "Jan", february: "Feb", march: "Mar", april: "Apr", may: "May",
  june: "Jun", july: "Jul", august: "Aug", september: "Sep", october: "Oct",
  november: "Nov", december: "Dec",
};
const MKB_ASSUMED_BITRATE_BPS = 128_000; // standard broadcast-MP3 rate
const MKB_PROXY_URL =
  "https://jjoxowdvzmlchtfarpbs.supabase.co/functions/v1/mkb-audio-proxy";

// playhls.media.nic.in sends an incomplete TLS chain (leaf issued by Let's
// Encrypt "YR1", but the server serves the wrong intermediate) — Deno's
// fetch rejects it outright unless given the real YR1 cert to complete the
// chain itself. Same fix as mkb-audio-proxy, needed here too since the
// duration probe below talks to this host directly.
const YR1_INTERMEDIATE_PEM = `-----BEGIN CERTIFICATE-----
MIIE2zCCAsOgAwIBAgIRAKICU/FfJpHAXcHOE7m8yk4wDQYJKoZIhvcNAQELBQAw
LjELMAkGA1UEBhMCVVMxDTALBgNVBAoTBElTUkcxEDAOBgNVBAMTB1Jvb3QgWVIw
HhcNMjUwOTAzMDAwMDAwWhcNMjgwOTAyMjM1OTU5WjAzMQswCQYDVQQGEwJVUzEW
MBQGA1UEChMNTGV0J3MgRW5jcnlwdDEMMAoGA1UEAxMDWVIxMIIBIjANBgkqhkiG
9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoVi8X2xCYgMXvJxNPKp/oF13UMgmPABB07VC
LNDtoXmt9luEZNJSBV10VyT1Pz6LD8Zq1d2gc43WNl1AdRrj4sEnazbOiz0nPpmG
Bp2hui49oZtDIY6wdKeZAi5BbNU20CH6RSBBMLSQ9cXrH8dxdv4PAJ45ssGML68U
SE3BsjC2a6cAN9L5CgXVIQi5tfNiTPoFZZ3S0OlXqLmmtdV95udWAb5b6e/F49Di
CsH0Y00Ag72BVIb1hzynmKe+X0mERBTtsb3BwmpV9ipeBjMLoR/D9cHxHQCWoi5l
TmXwY015J5rGelz1nZjJuxc2kioaX29XJBnhMkP531rSdG5uMwIDAQABo4HuMIHr
MA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEFBQcDATASBgNVHRMBAf8E
CDAGAQH/AgEAMB0GA1UdDgQWBBQfLzW+RhSCzUCxrnksVXj699Ro+zAfBgNVHSME
GDAWgBTe51tg0CJtQCh9Pw0B/qS1UrRRlDAyBggrBgEFBQcBAQQmMCQwIgYIKwYB
BQUHMAKGFmh0dHA6Ly95ci5pLmxlbmNyLm9yZy8wEwYDVR0gBAwwCjAIBgZngQwB
AgEwJwYDVR0fBCAwHjAcoBqgGIYWaHR0cDovL3lyLmMubGVuY3Iub3JnLzANBgkq
hkiG9w0BAQsFAAOCAgEA0+zvMq3kHig1ddTmmm+RibTr9/RpX7k4buanMMRqbV/y
IvP82zAHN3mvaw+cASuVsdpd0ikjhr4hnhJQLQOzOp2ccKrsdGOAgo0vddeISFAq
EWEV4lmUM3vFF796up+bSgmJ1u6RupDCMxDgF8M3eLvGuj6L0lu3zkQ0KuQLnKxL
tB0oQqn1Idg5CuuGpMvQzk29Pa3D/qHurc0EIM9SxukQuJqq63lxsYyRQFU8yMBO
hq1w5LbfaWNRrz1uklOfI/pYkAb2E2MTZrAMQkBIE2S8Jt1F8gRc96o/xOsrgvSk
a84AisX6xq1lz1Z7jGvrnXc4TMcjxZTjiTaihcYI1JIXZiLtEMSCa5l3cu8YWd6z
dLRQlqRdclVjuQfNHawRJ6GWlkK0QJosivTKwdBw3KxEtzGo8yMHERbsy57gP1UX
HOMcmZYQC0gtyR3SxfenIM/MxC3Ia2Ypab/kQ/CTnlIn2KQ5JUC6NYrGCbhFN9bp
5lKJStEwCUnLpntcrXk5XVDCNv/5RyWpRThkGOV7GetKkQ0qAY8hCzWK6oqnAhDZ
cjlYVdWfqOw3DIOX6EDNBgAqHarRVxyF9QZdOaXSyPJ0ueD2BYJEBgaCGQ8rAaU/
Qc123V5LTXDZW4CcsPBDyhy4v+c8hClAyw/IkJlfBqxB9D+/wvIMHgECZ4ptP6o=
-----END CERTIFICATE-----`;
const mkbUpstreamClient = Deno.createHttpClient({
  caCerts: [YR1_INTERMEDIATE_PEM],
});

async function fetchMannKiBaat(): Promise<Episode | null> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 12000);
  try {
    const r = await fetch(PMO_RADIO_URL, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)" },
      signal: ctrl.signal,
    });
    if (!r.ok) return null;
    const html = await r.text();
    // <body onload="hideallexcept('div135');"> names the newest episode's div.
    const onloadMatch = html.match(/onload="hideallexcept\('(div\d+)'\)/);
    const divId = onloadMatch?.[1];
    if (!divId) return null;
    // Its "Part-XX, DDth Month YYYY" caption sits in the same block's
    // <center> link, right after the matching hideallexcept(divId) onclick.
    // The day's ordinal suffix is wrapped in <sup>, e.g. "28<sup>th</sup>
    // June 2026" — capture across inner tags, then strip them.
    const captionMatch = html.match(
      new RegExp(`hideallexcept\\('${divId}'\\);"[^>]*><center>([\\s\\S]*?)</center>`),
    );
    const caption = captionMatch
      ? captionMatch[1].replace(/<[^>]+>/g, "").trim()
      : "";
    const dateMatch = caption.match(/(\d{1,2})\w*\s+([A-Za-z]+)\s+(\d{4})/);
    if (!dateMatch) return null;
    const [, day, monthName, year] = dateMatch;
    const mon = MKB_MONTHS[monthName.toLowerCase()];
    if (!mon) return null;
    const pubDate = `${day.padStart(2, "0")} ${mon} ${year} 00:00:00 +0000`;

    // Base64-encode the div id and POST it — exactly what hideallexcept()
    // does client-side.
    const b64 = btoa(divId);
    const pr = await fetch(
      `https://pmonradio.nic.in/pcvideocode.asp?id=${b64}`,
      {
        method: "POST",
        headers: {
          "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)",
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: "",
        signal: ctrl.signal,
      },
    );
    if (!pr.ok) return null;
    const playerHtml = await pr.text();
    // Two <iframe>s come back — a live .m3u8 one (inside an HTML comment)
    // and the real vod .mp3 one. Matching for the .mp3 suffix picks the
    // right one regardless of the comment.
    const mp3Match = playerHtml.match(/hlsurl=(\/\/[^&"]+\.mp3)/);
    if (!mp3Match) return null;
    const upstreamUrl = `https:${mp3Match[1]}`;

    // Duration estimate via a byte-range probe through the proxy (the raw
    // CDN would 403 a bare request with no Referer).
    let durationSeconds = 0;
    try {
      const rr = await fetch(upstreamUrl, {
        client: mkbUpstreamClient,
        headers: {
          "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)",
          "Referer": PMO_RADIO_URL,
          "Range": "bytes=0-1",
        },
        signal: ctrl.signal,
      });
      const range = rr.headers.get("content-range");
      const total = range ? parseInt(range.split("/")[1] ?? "0", 10) : 0;
      if (total > 0) {
        durationSeconds = Math.round((total * 8) / MKB_ASSUMED_BITRATE_BPS);
      }
    } catch {
      // best-effort
    }

    return {
      key: "mann_ki_baat",
      title: "Mann Ki Baat",
      episodeTitle: `Mann Ki Baat — ${caption}`,
      audioUrl: `${MKB_PROXY_URL}?src=${encodeURIComponent(upstreamUrl)}`,
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
      fetchAirTelugu().then((e) => e ?? airFromStorage()),
      fetchMannKiBaat(),
    ]);
    const items = results.filter((x): x is Episode => x !== null);
    return json({ ok: true, items });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[feeds-podcasts]", err);
    return json({ error: "podcasts_failed", message }, 500);
  }
});
