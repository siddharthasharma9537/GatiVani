import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import * as r2 from "../_shared/r2.ts";
// Sarvam STT forced-alignment (./alignment.ts) is disabled for cost — see the
// commented-out alignAndStore call in the handler.
// (touch: retrigger deploy now that the CI loop skips _shared)

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-subscription-tier",
};

// TTS runs on GatiVāni's own shared key now (verify_jwt=true already requires
// a signed-in caller). Caching bounds cost to unique content, not readers —
// but the synthesize endpoint still accepts arbitrary `text`, so nothing
// stops a signed-in caller from burning quota on text that isn't a real
// article. sub() + a per-user rate limit are the two backstops for that,
// alongside the content-match check further down for real articleIds.
function jwtSub(req: Request): string {
  try {
    const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    return payload.sub ?? "";
  } catch {
    return "";
  }
}

// Stores synthesized audio and returns its public URL, or "" when it could not
// be stored (callers fall back to a data: URI, so playback still works).
//
// R2 wins when it is configured; there is deliberately no fallback to the
// Supabase bucket on an R2 failure, since the point of the migration is to stop
// writing audio there — see docs/R2_AUDIO_MIGRATION.md. Until the credentials
// are set, this keeps using Supabase Storage exactly as before.
// deno-lint-ignore no-explicit-any
async function storeAudio(supabase: any, path: string, bytes: Uint8Array): Promise<string> {
  if (r2.configured()) {
    try {
      await r2.put(path, bytes, "audio/wav");
      return r2.publicUrl(path);
    } catch (e) {
      console.warn("[synthesize] r2 upload failed:", e);
      return "";
    }
  }
  if (!supabase) return "";
  const { error } = await supabase.storage
    .from("audio")
    .upload(path, bytes, { contentType: "audio/wav", upsert: true });
  if (error) {
    console.warn("[synthesize] audio upload failed:", error.message);
    return "";
  }
  return supabase.storage.from("audio").getPublicUrl(path).data.publicUrl;
}

// deno-lint-ignore no-explicit-any
async function checkUserRateLimit(supabase: any, userId: string): Promise<boolean> {
  const oneHourAgo = new Date(Date.now() - 3600_000).toISOString();
  const { count } = await supabase
    .from("request_log").select("*", { count: "exact", head: true })
    .eq("ip", `user:${userId}`).eq("endpoint", "documents-synthesize")
    .gte("created_at", oneHourAgo);
  if ((count ?? 0) >= 120) return false;
  await supabase.from("request_log").insert({ ip: `user:${userId}`, endpoint: "documents-synthesize" });
  return true;
}

// ── Language config ────────────────────────────────────────────────────────────

const LANGUAGE_CONFIG: Record<string, { code: string; sampleRate: number; speaker: string }> = {
  te: { code: "te-IN", sampleRate: 48000, speaker: "shubh" },
  hi: { code: "hi-IN", sampleRate: 22050, speaker: "tanya" },
  en: { code: "en-IN", sampleRate: 22050, speaker: "amit" },
};

// ── TTS provider ────────────────────────────────────────────────────────────────
// Gemini 2.5 Flash TTS for every tier. Sarvam TTS was removed (cost) — see the
// main handler; there is no Sarvam TTS fallback.

// ── Gemini voice mapping ───────────────────────────────────────────────────────
// Sarvam female voices → Kore (clear, warm female)
// Sarvam male voices   → Puck (natural male)

// Includes the Hindi default speaker ("tanya") alongside the Telugu names —
// this set is really "known female voice names across languages", not
// Telugu-only, despite its name.
const FEMALE_SARVAM = new Set(["priya", "neha", "kavya", "shreya", "suhani", "kavitha", "tanya"]);

function geminiVoice(speaker: string): string {
  return FEMALE_SARVAM.has(speaker.toLowerCase()) ? "Kore" : "Puck";
}

// ── Google Cloud TTS ──────────────────────────────────────────────────────────
// Same synthesis job, different product from Gemini TTS — and the reason to
// move is quota, not quality. The Gemini Developer API's free tier for
// gemini-2.5-flash-preview-tts is 15 requests PER DAY, which is roughly three
// articles; past that every call 429s and playback dies at the first chunk
// boundary. Cloud TTS is rate-limited per MINUTE (1,000 RPM for Standard) with
// 4M free characters a month, so the daily wall disappears entirely.
//
// Standard voices are the cheap tier: te-IN has exactly four (A/C female,
// B/D male). They are audibly flatter than Chirp 3: HD (which carries the same
// Kore/Puck voices this app shipped with) — a deliberate trade for staying
// inside the free allowance. Switching tiers later is a one-string change to
// the voice name below; nothing else here cares.
const GOOGLE_TTS_ENDPOINT = "https://texttospeech.googleapis.com/v1/text:synthesize";
// Cloud TTS caps a request at 5,000 BYTES — not characters. Telugu is 3 bytes
// per character in UTF-8, so the real ceiling is ~1,660 Telugu characters and
// any chunker measuring String.length will pass English tests and fail on
// Telugu. Everything below measures bytes; 4,000 leaves room for the JSON
// envelope and for a stray 4-byte codepoint.
const GOOGLE_TTS_BYTE_LIMIT = 4000;

function googleVoice(speaker: string, langCode: string): string {
  const female = FEMALE_SARVAM.has(speaker.toLowerCase());
  return `${langCode}-Standard-${female ? "A" : "B"}`;
}

// One Cloud TTS call → a complete WAV. LINEAR16 responses carry a WAV header,
// and pinning sampleRateHertz to GEMINI_SAMPLE_RATE keeps the byte-length
// duration maths below identical to the Gemini path's.
async function googleOneCall(
  text: string,
  voiceName: string,
  langCode: string,
  apiKey: string,
): Promise<Uint8Array> {
  const resp = await fetch(`${GOOGLE_TTS_ENDPOINT}?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      input: { text },
      voice: { languageCode: langCode, name: voiceName },
      audioConfig: {
        audioEncoding: "LINEAR16",
        sampleRateHertz: GEMINI_SAMPLE_RATE,
      },
    }),
  });
  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Google TTS HTTP ${resp.status}: ${errText.slice(0, 200)}`);
  }
  const data = await resp.json() as { audioContent?: string };
  if (!data.audioContent) throw new Error("Google TTS: no audioContent in response");
  return base64ToBytes(data.audioContent);
}

// Which provider serves this deploy. Google Cloud TTS wins whenever its key is
// present; without it nothing changes and Gemini keeps serving, so this can be
// rolled back by clearing one secret rather than redeploying.
function ttsProvider(): "google" | "gemini" {
  const forced = Deno.env.get("TTS_PROVIDER");
  if (forced === "gemini") return "gemini";
  return Deno.env.get("GOOGLE_TTS_API_KEY") ? "google" : "gemini";
}

// Synthesize ONE chunk with whichever provider is active.
async function synthesizeOneCall(
  text: string,
  speaker: string,
  langCode: string,
): Promise<Uint8Array> {
  if (ttsProvider() === "google") {
    return await googleOneCall(
      text,
      googleVoice(speaker, langCode),
      langCode,
      Deno.env.get("GOOGLE_TTS_API_KEY")!,
    );
  }
  return await geminiOneCall(text, geminiVoice(speaker), Deno.env.get("GEMINI_API_KEY")!);
}

// UTF-8 byte length — what Cloud TTS actually counts, and what Telugu makes
// diverge sharply from String.length.
const enc = new TextEncoder();
function byteLen(s: string): number {
  return enc.encode(s).length;
}

// The chunk sizing in force for the active provider, and whether it is measured
// in bytes or characters.
function chunkLimits(): { limit: number; byBytes: boolean } {
  return ttsProvider() === "google"
    ? { limit: GOOGLE_TTS_BYTE_LIMIT, byBytes: true }
    : { limit: GEMINI_CHUNK_LIMIT, byBytes: false };
}

// ── Sarvam chunking ───────────────────────────────────────────────────────────
// Sarvam Bulbul:v3 hard limit is 500 chars; stay safely under it.

const SARVAM_CHUNK_LIMIT = 450;
// Per-chunk size for Gemini TTS. Real-world measurement (chunk upload
// timestamps across several live plays) shows a single call's latency does
// NOT scale predictably with chunk length in the few-hundred-to-1.5k-char
// range — identically-sized ~350-char chunks back to back have taken
// anywhere from 15s to over a minute, most likely dominated by Gemini API
// queueing/rate-limit behavior on the caller's own key rather than by text
// length. That means shrinking chunk size doesn't reliably buy speed, but it
// DOES multiply how many Gemini calls one article needs — worse for a
// rate-limited key, not better. So: keep GEMINI_CHUNK_LIMIT sized for
// call-count efficiency (used by both the legacy parallel full-synthesis
// path AND as the size of every chunk-mode chunk after the first), not for
// fitting inside any particular playback window.
const GEMINI_CHUNK_LIMIT = 1450;

// [limit] bounds every part.
// [byBytes] switches the measure from characters to UTF-8 bytes. Google Cloud
// TTS enforces a BYTE cap, and Telugu costs 3 bytes per character, so measuring
// String.length there silently builds chunks ~3x over the wire limit — passing
// every English test and failing on the only language this app ships.
function chunkText(
  text: string,
  limit: number = SARVAM_CHUNK_LIMIT,
  byBytes = false,
): string[] {
  const m = byBytes ? byteLen : (s: string) => s.length;
  if (m(text) <= limit) return [text];
  const chunks: string[] = [];
  const sentences = text.split(/(?<=[।॥|.!?\n])\s*/u).filter(s => s.trim());
  let current = "";
  for (const sentence of sentences) {
    if (m(sentence) > limit) {
      if (current.trim()) { chunks.push(current.trim()); current = ""; }
      const words = sentence.split(/\s+/);
      let part = "";
      for (const word of words) {
        if (m(part + " " + word) > limit) {
          if (part.trim()) chunks.push(part.trim());
          part = word;
        } else {
          part = part ? part + " " + word : word;
        }
      }
      if (part.trim()) current = part.trim();
    } else if (m(current + " " + sentence) > limit) {
      if (current.trim()) chunks.push(current.trim());
      current = sentence;
    } else {
      current = current ? current + " " + sentence : sentence;
    }
  }
  if (current.trim()) chunks.push(current.trim());
  return chunks.filter(c => c.length > 0);
}

// ── WAV utilities ─────────────────────────────────────────────────────────────

function buildWavHeader(
  pcmByteLength: number,
  sampleRate: number,
  channels = 1,
  bitsPerSample = 16,
): Uint8Array {
  const header = new Uint8Array(44);
  const view = new DataView(header.buffer);
  const byteRate = sampleRate * channels * (bitsPerSample / 8);
  const blockAlign = channels * (bitsPerSample / 8);

  header.set([0x52, 0x49, 0x46, 0x46], 0); // "RIFF"
  view.setUint32(4, 36 + pcmByteLength, true);
  header.set([0x57, 0x41, 0x56, 0x45], 8); // "WAVE"
  header.set([0x66, 0x6d, 0x74, 0x20], 12); // "fmt "
  view.setUint32(16, 16, true);    // chunk size
  view.setUint16(20, 1, true);     // PCM
  view.setUint16(22, channels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);
  header.set([0x64, 0x61, 0x74, 0x61], 36); // "data"
  view.setUint32(40, pcmByteLength, true);
  return header;
}

function concatWavBuffers(buffers: Uint8Array[]): Uint8Array {
  if (buffers.length === 1) return buffers[0];
  const HEADER = 44;
  const firstHeader = buffers[0].slice(0, HEADER);
  const allPcm = buffers.map(b => b.slice(HEADER));
  const pcmTotal = allPcm.reduce((s, p) => s + p.length, 0);
  const result = new Uint8Array(HEADER + pcmTotal);
  result.set(firstHeader, 0);
  let offset = HEADER;
  for (const pcm of allPcm) { result.set(pcm, offset); offset += pcm.length; }
  const view = new DataView(result.buffer);
  view.setUint32(4, result.length - 8, true);
  view.setUint32(40, pcmTotal, true);
  return result;
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

// The audio cache (articles.audio_url/summary_audio_url) is
// keyed on a caller-supplied articleId with no other proof the caller's text
// actually belongs to that article. Hashing the text and requiring it to
// match on every cache read means a caller can't silently overwrite another
// article's cached audio with arbitrary content — a mismatch is just treated
// as a cache miss and re-synthesized from what THIS caller sent, so a
// mismatched/poisoned entry self-corrects the next time someone with the
// real text requests it, rather than being a permanent, silent takeover.
async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ── Reading-style prompt wrapper ──────────────────────────────────────────────

function styledText(text: string, readingStyle?: string): string {
  switch (readingStyle) {
    case "news_anchor":
      return `Read the following as a professional Telugu news anchor. Speak clearly and at an engaging pace:\n\n${text}`;
    case "devotional_slow":
      return `Read the following devotional content with reverence and calm. Speak slowly and clearly, pausing naturally between sentences:\n\n${text}`;
    case "mantra_clear":
      return `Read the following Sanskrit text very slowly and clearly. Pronounce each syllable distinctly with proper pausing between words:\n\n${text}`;
    default:
      return text;
  }
}

// ── Gemini 2.5 Flash TTS ──────────────────────────────────────────────────────
// Returns raw PCM int16 LE at 24 kHz mono — no chunking needed.

const GEMINI_SAMPLE_RATE = 24000;

// One Gemini TTS call → a complete WAV for the given text. Retries once on
// 429 (rate limit) after a short backoff — now that there's no Sarvam
// fallback to fall through to, a 429 with no retry just kills the request.
// Any other error still fails fast (no fallback to preserve budget for).
async function geminiOneCall(
  text: string,
  voiceName: string,
  geminiKey: string,
): Promise<Uint8Array> {
  const doFetch = () => fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=${geminiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text }] }],
        generationConfig: {
          responseModalities: ["AUDIO"],
          speechConfig: {
            voiceConfig: { prebuiltVoiceConfig: { voiceName } },
          },
        },
      }),
    },
  );

  let resp = await doFetch();
  if (resp.status === 429) {
    await new Promise((r) => setTimeout(r, 2000));
    resp = await doFetch();
  }

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Gemini TTS HTTP ${resp.status}: ${errText.slice(0, 200)}`);
  }

  const data = await resp.json() as {
    candidates?: Array<{
      content?: { parts?: Array<{ inlineData?: { data?: string } }> };
    }>;
  };
  const rawB64 = data?.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data;
  if (!rawB64) throw new Error("Gemini TTS: no audio data in response");

  const pcmBytes = base64ToBytes(rawB64);
  const header = buildWavHeader(pcmBytes.length, GEMINI_SAMPLE_RATE);
  const wavBytes = new Uint8Array(44 + pcmBytes.length);
  wavBytes.set(header, 0);
  wavBytes.set(pcmBytes, 44);
  return wavBytes;
}

async function synthesizeFull(
  text: string,
  speaker: string,
  langCode: string,
  readingStyle?: string,
): Promise<{ wavBytes: Uint8Array; durationSec: number; chunks: number }> {
  // Gemini works best with natural content — don't inject English instructions
  // into Telugu text. Standard voices ignore style prompts outright.
  const { limit, byBytes } = chunkLimits();
  const parts = chunkText(text, limit, byBytes);
  console.log(
    `[tts] provider=${ttsProvider()} ${text.length} chars → ${parts.length} chunk(s), style=${readingStyle ?? "default"}`,
  );

  // Chunks still run concurrently (wall time ≈ one chunk, not the sum), but
  // their start times are staggered rather than fired in one simultaneous
  // burst — a burst against one caller's own rate-limited key is the likely
  // trigger for the 429s geminiOneCall now retries once. Staggering spreads
  // that same set of calls out so fewer land in the same rate-limit window.
  const STAGGER_MS = 500;
  const wavs = await Promise.all(
    parts.map(async (p, i) => {
      if (i > 0) await new Promise((r) => setTimeout(r, i * STAGGER_MS));
      return synthesizeOneCall(p, speaker, langCode);
    }),
  );
  const wavBytes = concatWavBuffers(wavs);
  const durationSec = Math.round((wavBytes.length - 44) / (GEMINI_SAMPLE_RATE * 2));
  return { wavBytes, durationSec, chunks: parts.length };
}

// ── Response helper ───────────────────────────────────────────────────────────

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // Either provider's key satisfies this — ttsProvider() picks between them.
  if (!Deno.env.get("GOOGLE_TTS_API_KEY") && !Deno.env.get("GEMINI_API_KEY")) {
    return json({ error: "config_missing" }, 500);
  }

  try {
    const body = await req.json().catch(() => null);
    if (!body || typeof body.text !== "string") {
      return json({ error: "missing_text", message: 'Expected "text" field in body.' }, 400);
    }
    const text = body.text.trim();
    if (!text) return json({ error: "empty_text", message: "Text cannot be empty." }, 400);
    // Audio depends on which provider rendered it, not on the text alone, so
    // fold the provider into the hash — a provider switch is then a clean
    // cache miss and a re-synthesis rather than serving the old voice.
    const textHash = await sha256Hex(`${ttsProvider()}|${text}`);

    const langKey = (body.language || "te-IN").split("-")[0];
    const cfg = LANGUAGE_CONFIG[langKey] ?? LANGUAGE_CONFIG.te;
    const speaker = (body.speaker as string | undefined) || cfg.speaker;
    const readingStyle = (body.readingStyle as string | undefined) || undefined;

    // Optional audio cache: pass the article's DB uuid ("articleId") and the
    // generated audio is stored once in the public "audio" bucket and reused on
    // every later call — TTS is the dominant pipeline cost (~85%).
    const articleId = typeof body.articleId === "string" && body.articleId ? body.articleId : "";
    // Which cached audio this is: the full article ("audio_url", default) or the
    // short briefing/summary narration ("summary_audio_url"). They cache to
    // separate columns + storage paths so a brief and a full clip never collide.
    const target = body.target === "summary_audio_url"
      ? "summary_audio_url"
      : "audio_url";
    const fileSuffix = target === "summary_audio_url" ? ".brief.wav" : ".wav";
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    // Needed for the rate limit / content check below even when articleId is
    // absent (e.g. a Live article, which is never persisted in `articles`),
    // not just for the cache path.
    const supabase = (SUPABASE_URL && SERVICE_KEY)
      ? createClient(SUPABASE_URL, SERVICE_KEY)
      : null;

    const hashCol = target === "summary_audio_url" ? "summary_audio_text_hash" : "audio_text_hash";
    let articleRow: Record<string, string> | null = null;
    if (supabase && articleId) {
      const { data: row } = await supabase
        .from("articles").select(`${target}, ${hashCol}, title, full_content, content_preview`)
        .eq("id", articleId).maybeSingle();
      articleRow = row as Record<string, string> | null;
      const cachedUrl = articleRow?.[target];
      const cachedHash = articleRow?.[hashCol];
      // A hash mismatch means either this is the first write for this exact
      // text, or a previous caller wrote different text under this articleId
      // — either way, treat it as a miss and re-synthesize from THIS caller's
      // text rather than trusting a cache entry that doesn't provably match.
      if (cachedUrl && cachedHash === textHash) {
        console.log(`[synthesize] cache hit (${target}) for article ${articleId}`);
        return json({
          ok: true,
          audioUrl: cachedUrl,
          // word-level timings live next to the audio; the app falls back to
          // estimation if this 404s (alignment may still be running)
          timingsUrl: cachedUrl.replace(/\.wav$/, ".timings.json"),
          provider: "cache",
          language: langKey,
          speaker,
          chunks: 0,
          durationSeconds: null,
          cached: true,
        });
      }
    }

    // Content check: now that synthesis runs on a shared key, a signed-in
    // caller could otherwise POST arbitrary junk text under a real articleId
    // and burn shared quota on content nobody actually reads. When the row
    // exists, the submitted text for the FULL narration must match what's
    // actually stored — same construction as the client's own `spokenText`
    // getter (title + separator + body). Briefs skip this (lede-extraction
    // logic isn't worth replicating server-side) and rely on the rate limit
    // + length cap instead. Live articles have no `articles` row at all, so
    // there's nothing to check them against either — same fallback applies.
    if (articleRow && target === "audio_url") {
      const t = (articleRow.title ?? "").trim();
      const bodySrc = (articleRow.full_content ?? "").trim() || (articleRow.content_preview ?? "").trim();
      const sep = /[.?!।॥…]$/.test(t) ? "\n\n" : ".\n\n";
      const expected = t ? `${t}${sep}${bodySrc}` : bodySrc;
      const norm = (s: string) => s.replace(/\s+/g, " ").trim();
      if (norm(expected) !== norm(text)) {
        console.warn(`[synthesize] content mismatch for article ${articleId}`);
        return json({
          error: "content_mismatch",
          message: "Submitted text doesn't match this article's stored content.",
        }, 400);
      }
    } else if (!articleRow && text.length > 20000) {
      // No DB row to validate against (Live article, or an unrecognized
      // articleId) — a generous absolute length cap is the only backstop
      // available, well above any real article/brief.
      return json({ error: "text_too_long", message: "Text exceeds the maximum length." }, 400);
    }

    // TTS is Gemini 2.5 Flash ONLY, on GatiVāni's own shared key — narration
    // no longer requires each caller to bring their own (BYOK removed; the
    // content check above + the per-user rate limit below are what bound
    // cost now instead). Sarvam TTS remains disabled (cost) with no fallback.
    if (supabase) {
      const userId = jwtSub(req);
      if (userId && !(await checkUserRateLimit(supabase, userId))) {
        return json({ error: "rate_limited", message: "Narration limit reached — try again later." }, 429);
      }
    }

    const usedProvider = ttsProvider() === "google" ? "google-tts-standard" : "gemini-2.5";
    console.log(`[synthesize] provider=${usedProvider} chars=${text.length} speaker=${speaker}`);

    const { wavBytes, durationSec, chunks } =
      await synthesizeFull(text, speaker, cfg.code, readingStyle);

    console.log(`[synthesize] done: ${Math.round(wavBytes.length / 1024)} KB ~${durationSec}s via ${usedProvider}`);

    // Persist to the public audio bucket + articles.audio_url for reuse.
    // The app accepts both plain URLs and data: URIs in audioUrl.
    let audioUrl = "";
    let timingsUrl = "";
    if (supabase) {
      const path = `articles/${articleId}${fileSuffix}`;
      audioUrl = await storeAudio(supabase, path, wavBytes);
      if (audioUrl) {
        timingsUrl = audioUrl.replace(/\.wav$/, ".timings.json");
        const { error: updErr } = await supabase
          .from("articles").update({ [target]: audioUrl, [hashCol]: textHash }).eq("id", articleId);
        if (updErr) console.warn(`[synthesize] ${target} update failed:`, updErr.message);

        // Forced alignment (Sarvam STT word timestamps) for lyric highlighting
        // is DISABLED to avoid Sarvam cost — it ran a speech-to-text pass on
        // every full article. The player falls back to its built-in
        // proportional timing estimate, so read-along still works (just less
        // word-precise). To re-enable, restore the alignAndStore call here.
        // if (SARVAM_KEY && target === "audio_url") {
        //   (globalThis as any).EdgeRuntime?.waitUntil?.(alignAndStore({
        //     wavBytes, articleId, languageCode: body.language || "te-IN",
        //     sarvamKey: SARVAM_KEY, supabase,
        //   }));
        // }
      }
    }
    if (!audioUrl) audioUrl = `data:audio/wav;base64,${bytesToBase64(wavBytes)}`;

    return json({
      ok: true,
      audioUrl,
      timingsUrl: timingsUrl || null,
      provider: usedProvider,
      language: langKey,
      speaker,
      chunks,
      durationSeconds: durationSec,
      cached: false,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-synthesize]", err);
    return json({ error: "synthesis_failed", message }, 500);
  }
});
