import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// feeds-mkb-playlist — the full Mann Ki Baat archive (Part-1, Oct 2014 through
// the latest), scraped from the official PMO radio archive (pmonradio.nic.in).
// Two modes:
//   GET                  → list every episode (id + title + pubDate), recent→oldest.
//   GET ?resolve=<divId>  → resolve ONE episode's real audio URL (lazy — the
//                           list itself never touches pcvideocode.asp, only a
//                           tapped episode does).
//
// pmonradio.nic.in has no RSS/API. Each episode is a div revealed client-side
// by hideallexcept(divId) (js/image_slide.js), which base64-encodes the div id
// and POSTs it to pcvideocode.asp — see feeds-podcasts' fetchMannKiBaat for the
// single-latest-episode version of this same mechanism; this function
// generalizes it to every archived episode.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
};

function json(body: unknown, status = 200, maxAge = 21600) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": `public, max-age=${maxAge}`,
    },
  });
}

const PMO_RADIO_URL = "https://pmonradio.nic.in/";
const ARCHIVES_URL = "https://pmonradio.nic.in/archives.html";
const MKB_MONTHS: Record<string, string> = {
  january: "Jan", february: "Feb", march: "Mar", april: "Apr", may: "May",
  june: "Jun", july: "Jul", august: "Aug", september: "Sep", october: "Oct",
  november: "Nov", december: "Dec",
};

// playhls.media.nic.in serves an incomplete TLS chain (leaf issued by Let's
// Encrypt "YR1", but the server serves the wrong intermediate) — Deno's fetch
// rejects it outright unless given the real YR1 cert to complete the chain
// itself. Same fix as feeds-podcasts / mkb-audio-proxy.
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
const upstreamClient = Deno.createHttpClient({ caCerts: [YR1_INTERMEDIATE_PEM] });

const MKB_PROXY_URL =
  "https://jjoxowdvzmlchtfarpbs.supabase.co/functions/v1/mkb-audio-proxy";

interface MkbListItem {
  id: string; // the div id, e.g. "div135" — also the resolve key
  title: string; // "Mann Ki Baat — Part-82, 28th June 2026"
  pubDate: string; // RFC822-ish, matches the app's parser
}

// Extracts every {divId, caption} pair from a page's episode grid. Some pages
// have OLD/placeholder entries wrapped in HTML comments (including at least
// one with a made-up future date) — strip comments first so those never leak
// into the list.
function extractEpisodes(html: string): Array<{ divId: string; caption: string }> {
  const clean = html.replace(/<!--[\s\S]*?-->/g, "");
  const re = /hideallexcept\('(div\d+)'\);"[^>]*><center>([\s\S]*?)<\/center>/g;
  const seen = new Set<string>();
  const out: Array<{ divId: string; caption: string }> = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(clean)) !== null) {
    const divId = m[1];
    if (seen.has(divId)) continue;
    seen.add(divId);
    const caption = m[2].replace(/<[^>]+>/g, "").trim();
    out.push({ divId, caption });
  }
  return out;
}

function captionToPubDate(caption: string): string | null {
  const m = caption.match(/(\d{1,2})\w*\s+([A-Za-z]+)\s+(\d{4})/);
  if (!m) return null;
  const [, day, monthName, year] = m;
  const mon = MKB_MONTHS[monthName.toLowerCase()];
  if (!mon) return null;
  return `${day.padStart(2, "0")} ${mon} ${year} 00:00:00 +0000`;
}

async function fetchPage(url: string): Promise<string | null> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 12000);
  try {
    const r = await fetch(url, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)" },
      signal: ctrl.signal,
    });
    if (!r.ok) return null;
    return await r.text();
  } catch {
    return null;
  } finally {
    clearTimeout(t);
  }
}

async function listEpisodes(): Promise<MkbListItem[]> {
  const [home, archives] = await Promise.all([
    fetchPage(PMO_RADIO_URL),
    fetchPage(ARCHIVES_URL),
  ]);
  const seen = new Set<string>();
  const items: MkbListItem[] = [];
  for (const html of [home, archives]) {
    if (!html) continue;
    for (const { divId, caption } of extractEpisodes(html)) {
      if (seen.has(divId)) continue;
      const pubDate = captionToPubDate(caption);
      if (!pubDate) continue;
      seen.add(divId);
      items.push({ id: divId, title: `Mann Ki Baat — ${caption}`, pubDate });
    }
  }
  items.sort((a, b) => (Date.parse(b.pubDate) || 0) - (Date.parse(a.pubDate) || 0));
  return items;
}

async function resolveEpisode(
  divId: string,
): Promise<{ audioUrl: string; durationSeconds: number } | null> {
  if (!/^div\d+$/.test(divId)) return null; // only ever a site-assigned div id
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 12000);
  try {
    const b64 = btoa(divId);
    const pr = await fetch(`https://pmonradio.nic.in/pcvideocode.asp?id=${b64}`, {
      method: "POST",
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: "",
      signal: ctrl.signal,
    });
    if (!pr.ok) return null;
    const playerHtml = await pr.text();
    // Two <iframe>s come back — a live .m3u8 one (inside an HTML comment) and
    // the real vod .mp3 one; matching for the .mp3 suffix picks the right one.
    const mp3Match = playerHtml.match(/hlsurl=(\/\/[^&"]+\.mp3)/);
    if (!mp3Match) return null;
    const upstreamUrl = `https:${mp3Match[1]}`;

    let durationSeconds = 0;
    try {
      const rr = await fetch(upstreamUrl, {
        client: upstreamClient,
        headers: {
          "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)",
          "Referer": PMO_RADIO_URL,
          "Range": "bytes=0-1",
        },
        signal: ctrl.signal,
      });
      const range = rr.headers.get("content-range");
      const total = range ? parseInt(range.split("/")[1] ?? "0", 10) : 0;
      if (total > 0) durationSeconds = Math.round((total * 8) / 128_000);
    } catch {
      // best-effort
    }

    return {
      audioUrl: `${MKB_PROXY_URL}?src=${encodeURIComponent(upstreamUrl)}`,
      durationSeconds,
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
    const url = new URL(req.url);
    const resolveDiv = url.searchParams.get("resolve");
    if (resolveDiv) {
      const resolved = await resolveEpisode(resolveDiv);
      if (!resolved) return json({ ok: false, error: "resolve_failed" }, 404, 0);
      return json({ ok: true, ...resolved }, 200, 3600);
    }
    const items = await listEpisodes();
    return json({ ok: true, count: items.length, items });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[feeds-mkb-playlist]", err);
    return json({ error: "mkb_playlist_failed", message }, 500, 0);
  }
});
