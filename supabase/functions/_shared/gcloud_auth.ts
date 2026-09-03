// Google Cloud OAuth 2.0 access tokens from a service account, inside Deno.
//
// Cloud Text-to-Speech does NOT accept `?key=API_KEY` the way the Gemini
// Developer API does — it requires a real OAuth bearer token. There is no
// `gcloud` and no Application Default Credentials inside an edge function, so
// the service-account JWT flow is implemented here directly:
//
//   1. build a JWT claiming the service account and the cloud-platform scope
//   2. sign it RS256 with the account's private key (WebCrypto)
//   3. exchange it at oauth2.googleapis.com/token for an access token
//
// Tokens last an hour, so they are cached in module scope. Edge function
// instances are reused between invocations, which means most calls pay nothing
// for auth; a cold start pays one extra round trip.
//
// ── Setup ───────────────────────────────────────────────────────────────────
//   1. Create a service account with the "Cloud Text-to-Speech User" role.
//   2. Create a JSON key for it.
//   3. supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON="$(cat key.json)"
//
// The JSON is stored whole rather than as separate fields so rotating the key
// is a single secret update, and so a partially-updated credential can never
// be assembled from mismatched halves.

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id?: string;
}

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/cloud-platform";
/** Refresh this many seconds before actual expiry, so a token never dies mid-request. */
const EXPIRY_SKEW_S = 300;

let cachedToken: { value: string; expiresAt: number } | null = null;
let inFlight: Promise<string> | null = null;

export function serviceAccountConfigured(): boolean {
  return !!Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
}

function loadServiceAccount(): ServiceAccount {
  const raw = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("GOOGLE_SERVICE_ACCOUNT_JSON is not set");
  let sa: ServiceAccount;
  try {
    sa = JSON.parse(raw) as ServiceAccount;
  } catch {
    throw new Error("GOOGLE_SERVICE_ACCOUNT_JSON is not valid JSON");
  }
  if (!sa.client_email || !sa.private_key) {
    throw new Error("service account JSON is missing client_email or private_key");
  }
  return sa;
}

function b64url(bytes: Uint8Array | ArrayBuffer): string {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = "";
  // Chunked to avoid blowing the argument limit on large inputs.
  const CHUNK = 0x8000;
  for (let i = 0; i < b.length; i += CHUNK) {
    s += String.fromCharCode(...b.subarray(i, Math.min(i + CHUNK, b.length)));
  }
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * PEM → DER.
 *
 * Handles the literal `\n` sequences that survive when a service-account JSON
 * is pasted into a shell or an env var: without this the key body is one long
 * line containing backslash-n and the import fails with an opaque error.
 */
function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

async function mintToken(): Promise<string> {
  const sa = loadServiceAccount();
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const enc = new TextEncoder();
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = b64url(enc.encode(JSON.stringify({
    iss: sa.client_email,
    scope: SCOPE,
    aud: TOKEN_URL,
    exp: now + 3600,
    iat: now,
  })));
  const signingInput = `${header}.${claim}`;
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    enc.encode(signingInput),
  );
  const assertion = `${signingInput}.${b64url(signature)}`;

  const resp = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
    signal: AbortSignal.timeout(15_000),
  });

  if (!resp.ok) {
    const detail = await resp.text().catch(() => "");
    throw new Error(`token exchange failed: HTTP ${resp.status} ${detail.slice(0, 200)}`);
  }

  const data = await resp.json() as { access_token?: string; expires_in?: number };
  if (!data.access_token) throw new Error("token exchange returned no access_token");

  cachedToken = {
    value: data.access_token,
    expiresAt: Date.now() + ((data.expires_in ?? 3600) - EXPIRY_SKEW_S) * 1000,
  };
  return cachedToken.value;
}

/**
 * A valid access token, minted on first use and reused until it nears expiry.
 *
 * Concurrent callers on a cold instance share one exchange rather than each
 * minting their own — synthesis fans out across chunks, so without this a
 * single article could trigger several identical token requests.
 */
export async function accessToken(): Promise<string> {
  if (cachedToken && Date.now() < cachedToken.expiresAt) return cachedToken.value;
  if (inFlight) return inFlight;
  inFlight = mintToken().finally(() => {
    inFlight = null;
  });
  return inFlight;
}

/** Drop the cached token. For tests, and for recovering from a 401. */
export function resetTokenCache(): void {
  cachedToken = null;
}
