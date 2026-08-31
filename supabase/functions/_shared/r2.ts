// Cloudflare R2 access for the audio bucket.
//
// R2 bindings (env.BUCKET.put) only exist inside Cloudflare Workers. These
// functions run on Deno on Supabase, so everything here goes through R2's
// S3-compatible API with SigV4-signed requests. This module is the only place
// that knows about signing — callers see put/head/list/remove/publicUrl and
// nothing else, so a later move to Workers bindings touches one file.
//
// See docs/R2_AUDIO_MIGRATION.md for the migration this is part of.

import { AwsClient } from "npm:aws4fetch@1.0.20";

const ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID") ?? "";
const ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID") ?? "";
const SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY") ?? "";
const BUCKET = Deno.env.get("R2_BUCKET") ?? "gativani-audio";

// Public base for playback URLs, e.g. https://audio.gativani.sohum.cloud
// (no trailing slash). These end up stored in articles.audio_url and friends,
// so changing it later means rewriting rows — see the migration doc.
const PUBLIC_BASE = (Deno.env.get("R2_PUBLIC_BASE") ?? "").replace(/\/+$/, "");

const ORIGIN = `https://${ACCOUNT_ID}.r2.cloudflarestorage.com`;

/** True when the credentials needed to write are all present. Callers should
 *  degrade to "no cached audio" rather than failing the request when false. */
export function configured(): boolean {
  return Boolean(ACCOUNT_ID && ACCESS_KEY_ID && SECRET_ACCESS_KEY && PUBLIC_BASE);
}

let _client: AwsClient | null = null;
function client(): AwsClient {
  if (!_client) {
    _client = new AwsClient({
      accessKeyId: ACCESS_KEY_ID,
      secretAccessKey: SECRET_ACCESS_KEY,
      service: "s3",
      region: "auto", // R2 is regionless; "auto" is what it expects in the sig
    });
  }
  return _client;
}

// Keys are used as URL path segments. R2 accepts "/" as a separator, so encode
// each segment rather than the whole key, or "articles/x.wav" becomes
// "articles%2Fx.wav" and the prefix layout is lost.
function encodeKey(key: string): string {
  return key.split("/").map(encodeURIComponent).join("/");
}

function objectUrl(key: string): string {
  return `${ORIGIN}/${BUCKET}/${encodeKey(key)}`;
}

/** Public playback URL for a key. Absolute, so stored rows stay valid even if
 *  some objects still live in Supabase Storage during the migration. */
export function publicUrl(key: string): string {
  return `${PUBLIC_BASE}/${encodeKey(key)}`;
}

export async function put(
  key: string,
  body: Uint8Array,
  contentType: string,
): Promise<void> {
  const res = await client().fetch(objectUrl(key), {
    method: "PUT",
    body,
    headers: { "content-type": contentType },
  });
  if (!res.ok) {
    throw new Error(`r2 put ${key} failed: ${res.status} ${await res.text()}`);
  }
}

/** Object size in bytes, or null when absent. Used to test cache hits. */
export async function head(key: string): Promise<number | null> {
  const res = await client().fetch(objectUrl(key), { method: "HEAD" });
  if (res.status === 404) return null;
  if (!res.ok) {
    throw new Error(`r2 head ${key} failed: ${res.status}`);
  }
  return Number(res.headers.get("content-length") ?? 0);
}

export interface R2Object {
  key: string;
  size: number;
  lastModified: Date;
}

// S3 ListObjectsV2 answers in XML and Deno has no DOMParser, so pull the three
// fields we need out of each <Contents> block directly. The shapes here are
// fixed by the S3 spec, which is why regex is safe for this and would not be
// for arbitrary XML.
function parseListXml(xml: string): { objects: R2Object[]; next: string | null } {
  const objects: R2Object[] = [];
  for (const m of xml.matchAll(/<Contents>([\s\S]*?)<\/Contents>/g)) {
    const block = m[1];
    const key = block.match(/<Key>([\s\S]*?)<\/Key>/)?.[1];
    if (!key) continue;
    objects.push({
      key: key
        .replace(/&amp;/g, "&").replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'"),
      size: Number(block.match(/<Size>(\d+)<\/Size>/)?.[1] ?? 0),
      lastModified: new Date(
        block.match(/<LastModified>([\s\S]*?)<\/LastModified>/)?.[1] ?? 0,
      ),
    });
  }
  const truncated = /<IsTruncated>true<\/IsTruncated>/.test(xml);
  const next = truncated
    ? xml.match(/<NextContinuationToken>([\s\S]*?)<\/NextContinuationToken>/)?.[1] ?? null
    : null;
  return { objects, next };
}

/** Every object under `prefix`, following continuation tokens.
 *
 *  NOTE: unlike Supabase's storage.list(), S3 returns keys in lexicographic
 *  order with no sortBy option. Callers that want "newest" must sort on
 *  lastModified themselves — see feeds-podcasts, which picks the latest AIR
 *  bulletin and would otherwise silently pick the wrong file. */
export async function list(prefix: string): Promise<R2Object[]> {
  const out: R2Object[] = [];
  let token: string | null = null;

  do {
    const url = new URL(`${ORIGIN}/${BUCKET}`);
    url.searchParams.set("list-type", "2");
    url.searchParams.set("prefix", prefix);
    url.searchParams.set("max-keys", "1000");
    if (token) url.searchParams.set("continuation-token", token);

    const res = await client().fetch(url.toString());
    if (!res.ok) {
      throw new Error(`r2 list ${prefix} failed: ${res.status} ${await res.text()}`);
    }
    const parsed = parseListXml(await res.text());
    out.push(...parsed.objects);
    token = parsed.next;
  } while (token);

  return out;
}

/** Delete objects, returning how many actually went. Individual failures are
 *  logged and skipped rather than aborting the batch — a retention sweep should
 *  remove what it can. Uses one DELETE per key (S3 batch delete needs a signed
 *  XML body with Content-MD5, which is not worth the complexity at our volume). */
export async function remove(keys: string[], concurrency = 8): Promise<number> {
  let removed = 0;
  for (let i = 0; i < keys.length; i += concurrency) {
    const slice = keys.slice(i, i + concurrency);
    const results = await Promise.all(
      slice.map(async (key) => {
        try {
          const res = await client().fetch(objectUrl(key), { method: "DELETE" });
          // S3 returns 204 for a delete, and also for a key that was already gone.
          if (!res.ok && res.status !== 404) {
            console.warn(`[r2] delete ${key} failed: ${res.status}`);
            return false;
          }
          return true;
        } catch (e) {
          console.warn(`[r2] delete ${key} threw:`, e);
          return false;
        }
      }),
    );
    removed += results.filter(Boolean).length;
  }
  return removed;
}
