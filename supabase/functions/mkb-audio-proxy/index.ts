import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// mkb-audio-proxy — streams Mann Ki Baat audio from pmonradio.nic.in's CDN
// (playhls.media.nic.in). That CDN 403s any request whose Referer isn't
// https://pmonradio.nic.in/ itself (anti-hotlink), but a browser <audio>
// element always sends the PAGE's own origin as Referer — and just_audio's
// custom `headers` option only works on native platforms, not Flutter web,
// so there's no way to fix this from the player. This proxy re-fetches the
// file server-side with the right Referer and streams the bytes through,
// forwarding the client's Range header so seeking still works.
//
// Locked to the one CDN host feeds-podcasts discovers Mann Ki Baat episodes
// from, so this can't be used as an open proxy for arbitrary URLs.

const ALLOWED_HOST = "playhls.media.nic.in";
const UPSTREAM_REFERER = "https://pmonradio.nic.in/";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info, range",
};

// playhls.media.nic.in serves an incomplete TLS chain: its leaf cert is
// issued by Let's Encrypt "YR1", but the server sends the WRONG intermediate
// ("R13") instead of YR1 itself. Browsers paper over this (cached/AIA-fetched
// intermediates), but Deno's fetch only trusts exactly what the server
// presents and fails with "invalid peer certificate: UnknownIssuer". Supplying
// the real YR1 intermediate (fetched straight from letsencrypt.org, itself
// signed by the well-trusted "ISRG Root YR") lets Deno complete the chain.
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

const upstreamClient = Deno.createHttpClient({
  caCerts: [YR1_INTERMEDIATE_PEM],
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const url = new URL(req.url);
    const src = url.searchParams.get("src");
    if (!src) {
      return new Response("missing src", { status: 400, headers: corsHeaders });
    }
    let upstream: URL;
    try {
      upstream = new URL(src);
    } catch {
      return new Response("invalid src", { status: 400, headers: corsHeaders });
    }
    if (upstream.hostname !== ALLOWED_HOST) {
      return new Response("host not allowed", { status: 400, headers: corsHeaders });
    }

    const range = req.headers.get("range");
    const r = await fetch(upstream.toString(), {
      client: upstreamClient,
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)",
        "Referer": UPSTREAM_REFERER,
        ...(range ? { "Range": range } : {}),
      },
    });

    const headers = new Headers(corsHeaders);
    headers.set("Content-Type", r.headers.get("content-type") ?? "audio/mpeg");
    headers.set("Cache-Control", "public, max-age=86400");
    headers.set("Accept-Ranges", "bytes");
    const cl = r.headers.get("content-length");
    if (cl) headers.set("Content-Length", cl);
    const cr = r.headers.get("content-range");
    if (cr) headers.set("Content-Range", cr);

    return new Response(r.body, { status: r.status, headers });
  } catch (err) {
    console.error("[mkb-audio-proxy]", err);
    const message = err instanceof Error ? err.message : String(err);
    return new Response(`proxy_failed: ${message}`, { status: 500, headers: corsHeaders });
  }
});
