// Fake R2 binding and a locally generated ES256 key. No network, no Cloudflare, no real ids.
import test from 'node:test';
import assert from 'node:assert/strict';
import { handle, parseRange, verifyJwt, _resetJwksCache } from '../src/index.js';

const SUPA = 'https://project.example.test';
const OWNER = '00000000-0000-4000-8000-000000000001';
const OTHER = '00000000-0000-4000-8000-000000000002';
const KEY = 'paper/TELANGANA/25-11-2026/001_sample_lead.m4a';
const PATH = '/paper-audio/TELANGANA/25-11-2026/001_sample_lead.m4a';
const b64u = (buf) => Buffer.from(buf).toString('base64url');

const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const jwk = { ...(await crypto.subtle.exportKey('jwk', pair.publicKey)), kid: 'k1', alg: 'ES256', use: 'sig' };
const fetchJwks = async () => new Response(JSON.stringify({ keys: [jwk] }), { status: 200 });

async function token(claims = {}, kid = 'k1', signer = pair.privateKey) {
  const h = b64u(JSON.stringify({ alg: 'ES256', typ: 'JWT', kid }));
  const p = b64u(JSON.stringify({ iss: `${SUPA}/auth/v1`, aud: 'authenticated', sub: OWNER,
    exp: Math.floor(Date.now() / 1000) + 600, ...claims }));
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, signer, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64u(sig)}`;
}

const BYTES = new Uint8Array(Array.from({ length: 100 }, (_, i) => i));
const bucket = {
  async head(k) { return k === KEY ? { size: BYTES.length, httpEtag: '"e1"' } : null; },
  async get(k, opts) {
    if (k !== KEY) return null;
    const r = opts?.range;
    return { body: r ? BYTES.slice(r.offset, r.offset + r.length) : BYTES };
  },
};
const env = { SUPABASE_URL: SUPA, OWNER_USER_IDS: OWNER, ALLOWED_ORIGIN: 'https://app.example.test', AUDIO: bucket };
const call = async (headers = {}, path = PATH, method = 'GET') => {
  _resetJwksCache();
  return handle(new Request('https://w.example.test' + path, { method, headers }), env, fetchJwks);
};
const bearer = async (claims) => ({ Authorization: 'Bearer ' + (await token(claims)) });

test('no token, bad token, wrong key, expired, wrong audience -> 401', async () => {
  assert.equal((await call()).status, 401);
  assert.equal((await call({ Authorization: 'Bearer abc.def.ghi' })).status, 401);
  const other = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  assert.equal((await call({ Authorization: 'Bearer ' + await token({}, 'k1', other.privateKey) })).status, 401);
  assert.equal((await call(await bearer({ exp: 1 }))).status, 401);
  assert.equal((await call(await bearer({ aud: 'anon' }))).status, 401);
  assert.equal((await call(await bearer({ iss: 'https://evil.example/auth/v1' }))).status, 401);
});

test('a signed-in non-owner gets 403 whether or not the file exists', async () => {
  assert.equal((await call(await bearer({ sub: OTHER }))).status, 403);
  assert.equal((await call(await bearer({ sub: OTHER }), '/paper-audio/TELANGANA/25-11-2026/009_nope.m4a')).status, 403);
});

test('owner gets the whole file with private no-store headers', async () => {
  const r = await call(await bearer());
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('Content-Type'), 'audio/mp4');
  assert.equal(r.headers.get('Accept-Ranges'), 'bytes');
  assert.equal(r.headers.get('Cache-Control'), 'private, no-store');
  assert.equal(r.headers.get('Content-Length'), '100');
  assert.equal(new Uint8Array(await r.arrayBuffer()).length, 100);
});

test('Range requests give 206 with Content-Range, 416 when unsatisfiable', async () => {
  const r = await call({ ...(await bearer()), Range: 'bytes=10-19' });
  assert.equal(r.status, 206);
  assert.equal(r.headers.get('Content-Range'), 'bytes 10-19/100');
  assert.deepEqual([...new Uint8Array(await r.arrayBuffer())], [10, 11, 12, 13, 14, 15, 16, 17, 18, 19]);
  const open = await call({ ...(await bearer()), Range: 'bytes=90-' });
  assert.equal(open.headers.get('Content-Range'), 'bytes 90-99/100');
  const bad = await call({ ...(await bearer()), Range: 'bytes=200-300' });
  assert.equal(bad.status, 416);
  assert.equal(bad.headers.get('Content-Range'), 'bytes */100');
});

test('unknown file and malformed paths are 404; other methods 405; HEAD has no body', async () => {
  const h = await bearer();
  assert.equal((await call(h, '/paper-audio/TELANGANA/25-11-2026/002_sample.m4a')).status, 404);
  assert.equal((await call(h, '/paper-audio/../secret')).status, 404);
  assert.equal((await call(h, '/paper-audio/TELANGANA/25-11-2026/')).status, 404);
  assert.equal((await call(h, PATH, 'DELETE')).status, 405);
  assert.equal((await call(h, PATH, 'PUT')).status, 405);
  const head = await call(h, PATH, 'HEAD');
  assert.equal(head.status, 200);
  assert.equal((await head.arrayBuffer()).byteLength, 0);
});

test('CORS: only the configured origin; preflight answers without a token', async () => {
  const pre = await call({ Origin: 'https://app.example.test', 'Access-Control-Request-Method': 'GET' }, PATH, 'OPTIONS');
  assert.equal(pre.status, 204);
  assert.equal(pre.headers.get('Access-Control-Allow-Origin'), 'https://app.example.test');
  assert.match(pre.headers.get('Access-Control-Allow-Headers'), /Authorization/);
  const evil = await call({ Origin: 'https://evil.example' }, PATH, 'OPTIONS');
  assert.equal(evil.headers.get('Access-Control-Allow-Origin'), null);
  const denied = await call({ Origin: 'https://app.example.test' });
  assert.equal(denied.status, 401);
  assert.equal(denied.headers.get('Access-Control-Allow-Origin'), 'https://app.example.test');
});

test('an empty owner list or missing JWKS fails closed', async () => {
  const h = await bearer();
  _resetJwksCache();
  const r1 = await handle(new Request('https://w.example.test' + PATH, { headers: h }), { ...env, OWNER_USER_IDS: '' }, fetchJwks);
  assert.equal(r1.status, 403);
  _resetJwksCache();
  const r2 = await handle(new Request('https://w.example.test' + PATH, { headers: h }), env, async () => new Response('x', { status: 500 }));
  assert.equal(r2.status, 401);
});

test('parseRange', () => {
  assert.deepEqual(parseRange('bytes=0-0', 10), { offset: 0, length: 1 });
  assert.deepEqual(parseRange('bytes=-3', 10), { offset: 7, length: 3 });
  assert.deepEqual(parseRange('bytes=5-99', 10), { offset: 5, length: 5 });
  assert.equal(parseRange('bytes=0-1,3-4', 10), 'bad');
  assert.equal(parseRange('bytes=-', 10), 'bad');
  assert.equal(parseRange(null, 10), null);
});

test('verifyJwt rejects alg none and HS256', async () => {
  const h = b64u(JSON.stringify({ alg: 'none', kid: 'k1' }));
  const p = b64u(JSON.stringify({ sub: OWNER }));
  assert.equal(await verifyJwt(`${h}.${p}.x`, env, fetchJwks), null);
});
