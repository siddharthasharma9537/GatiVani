// GatiVani paper-audio Worker: the ONLY way to play the private Paper audio.
// Contract: sohum-contracts docs/PAPER_AUDIO_SHAPE.md section 3. Read-only: no write, no list, no delete.
// Checks the signed-in Supabase user (JWT verified against the project's JWKS) against OWNER_USER_IDS,
// then streams from the R2 binding AUDIO with HTTP Range support. Fails closed on every doubt.

const KEY_RE = /^paper\/[A-Z][A-Z0-9-]*\/[0-9]{2}-[0-9]{2}-[0-9]{4}\/[0-9]{3}_[a-z0-9][a-z0-9_-]*\.m4a$/;
const ROUTE = /^\/paper-audio\/([A-Z][A-Z0-9-]*)\/([0-9]{2}-[0-9]{2}-[0-9]{4})\/([0-9]{3}_[a-z0-9][a-z0-9_-]*\.m4a)$/;
let jwksCache = { at: 0, keys: null };

const b64 = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
const json = (o) => JSON.parse(new TextDecoder().decode(b64(o)));

function cors(env, origin) {
  const allowed = (env.ALLOWED_ORIGIN || '').split(',').map((s) => s.trim()).filter(Boolean);
  const h = { Vary: 'Origin' };
  if (origin && allowed.includes(origin)) {
    h['Access-Control-Allow-Origin'] = origin;
    h['Access-Control-Allow-Headers'] = 'Authorization, Range';
    h['Access-Control-Allow-Methods'] = 'GET, HEAD, OPTIONS';
    h['Access-Control-Expose-Headers'] = 'Content-Range, Accept-Ranges, Content-Length, ETag';
    h['Access-Control-Max-Age'] = '600';
  }
  return h;
}

const reply = (status, headers, body = null) =>
  new Response(body, { status, headers: { 'Cache-Control': 'private, no-store', ...headers } });

async function jwks(env, fetchFn) {
  if (jwksCache.keys && Date.now() - jwksCache.at < 600000) return jwksCache.keys;
  const res = await fetchFn(`${env.SUPABASE_URL.replace(/\/$/, '')}/auth/v1/.well-known/jwks.json`);
  if (!res.ok) throw new Error('jwks');
  const keys = (await res.json()).keys || [];
  jwksCache = { at: Date.now(), keys };
  return keys;
}

/** Returns the user id (sub) of a valid Supabase access token, or null. Asymmetric keys only (ES256/RS256). */
export async function verifyJwt(token, env, fetchFn = fetch, nowSeconds = Math.floor(Date.now() / 1000)) {
  try {
    const [h, p, s] = token.split('.');
    if (!h || !p || !s) return null;
    const header = json(h), claims = json(p);
    const params = header.alg === 'ES256' ? { name: 'ECDSA', namedCurve: 'P-256' }
      : header.alg === 'RS256' ? { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' } : null;
    if (!params) return null;
    const jwk = (await jwks(env, fetchFn)).find((k) => k.kid === header.kid && (!k.alg || k.alg === header.alg));
    if (!jwk) return null;
    const key = await crypto.subtle.importKey('jwk', jwk, params, false, ['verify']);
    const verifyParams = header.alg === 'ES256' ? { name: 'ECDSA', hash: 'SHA-256' } : params;
    const ok = await crypto.subtle.verify(verifyParams, key, b64(s), new TextEncoder().encode(`${h}.${p}`));
    if (!ok) return null;
    const iss = `${env.SUPABASE_URL.replace(/\/$/, '')}/auth/v1`;
    if (claims.iss !== iss || claims.aud !== 'authenticated') return null;
    if (typeof claims.exp !== 'number' || claims.exp <= nowSeconds) return null;
    return typeof claims.sub === 'string' && claims.sub ? claims.sub : null;
  } catch {
    return null;
  }
}

/** Parses a single "bytes=a-b" range. Returns null (no range), 'bad' (unsatisfiable/invalid) or {offset,length}. */
export function parseRange(header, size) {
  if (!header) return null;
  const m = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!m || (m[1] === '' && m[2] === '')) return 'bad';
  let start, end;
  if (m[1] === '') {
    const n = Number(m[2]);
    if (n === 0) return 'bad';
    start = Math.max(0, size - n);
    end = size - 1;
  } else {
    start = Number(m[1]);
    end = m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1);
  }
  if (start >= size || start > end) return 'bad';
  return { offset: start, length: end - start + 1 };
}

export async function handle(request, env, fetchFn = fetch) {
  const url = new URL(request.url);
  const c = cors(env, request.headers.get('Origin'));
  if (request.method === 'OPTIONS') return reply(204, c);
  if (request.method !== 'GET' && request.method !== 'HEAD') return reply(405, { ...c, Allow: 'GET, HEAD, OPTIONS' });
  const route = ROUTE.exec(url.pathname);
  const token = /^Bearer (.+)$/.exec(request.headers.get('Authorization') || '')?.[1];
  if (!token) return reply(401, c);
  const sub = await verifyJwt(token, env, fetchFn);
  if (!sub) return reply(401, c);
  const owners = (env.OWNER_USER_IDS || '').split(',').map((s) => s.trim()).filter(Boolean);
  // 403 before any lookup: a non-owner learns nothing about whether a file exists.
  if (!owners.includes(sub)) return reply(403, c);
  if (!route) return reply(404, c);
  const key = `paper/${route[1]}/${route[2]}/${route[3]}`;
  if (!KEY_RE.test(key)) return reply(404, c);

  const head = await env.AUDIO.head(key);
  if (!head) return reply(404, c);
  const range = parseRange(request.headers.get('Range'), head.size);
  if (range === 'bad') return reply(416, { ...c, 'Content-Range': `bytes */${head.size}` });
  const base = { ...c, 'Content-Type': 'audio/mp4', 'Accept-Ranges': 'bytes', ETag: head.httpEtag };
  if (request.method === 'HEAD') return reply(200, { ...base, 'Content-Length': String(head.size) });
  const obj = await env.AUDIO.get(key, range ? { range } : undefined);
  if (!obj) return reply(404, c);
  if (!range) return reply(200, { ...base, 'Content-Length': String(head.size) }, obj.body);
  return reply(206, {
    ...base,
    'Content-Length': String(range.length),
    'Content-Range': `bytes ${range.offset}-${range.offset + range.length - 1}/${head.size}`,
  }, obj.body);
}

export default { fetch: (request, env) => handle(request, env) };
export const _resetJwksCache = () => { jwksCache = { at: 0, keys: null }; };
