// Google Cloud Text-to-Speech — the free lane.
//
// Why this exists: Gemini TTS bills every second of speech (~₹1.43/min), so a
// 3–4 hour edition costs more than ₹300 to narrate. Cloud TTS gives a monthly
// free pool per voice tier — Standard 4M characters, WaveNet 1M, Chirp 3 HD 1M
// — which is roughly 6M free characters a month, or ~30 editions. Narration
// stops being the dominant cost line and becomes, in practice, free.
// See docs/ORCHESTRATION_PLAN.md §2.3.
//
// It also returns MP3 directly, so the free lane skips the CPU cost of the
// lamejs encode that the Gemini path needs (_shared/mp3.ts).

import { accessToken } from "./gcloud_auth.ts";

const ENDPOINT = "https://texttospeech.googleapis.com/v1/text:synthesize";

/**
 * Which voice each surface speaks in.
 *
 * Pinned per surface rather than chosen dynamically. Past the free pools
 * Standard and WaveNet bill identically ($4/1M), so the assignment costs
 * nothing either way and can be made on quality and consistency instead —
 * and a pool draining mid-month must never silently change the voice of a
 * feed people hear every day. Reasoning in full: plan §2.3.
 */
export const VOICE_BY_SURFACE: Record<string, string> = {
  // Most-heard surface. Better voice at the same paid rate as Standard.
  live_article: "te-IN-Wavenet-A",
  // Falls back to the same voice as live_article so the ticker and the story
  // it opens never sound like two different narrators.
  live_ticker: "te-IN-Wavenet-A",
  // The long tail: the largest pool (4M) for the largest volume.
  edition_tail: "te-IN-Standard-A",
  // Prewarmed top stories (Phase 4). Best Cloud tier, strictly inside its
  // free pool — at $30/1M it must never be paid for.
  edition_top: "te-IN-Chirp3-HD-Achernar",
};

export type Surface = keyof typeof VOICE_BY_SURFACE;

export function voiceForSurface(surface: string): string {
  return VOICE_BY_SURFACE[surface] ?? VOICE_BY_SURFACE.edition_tail;
}

/** Language code is the voice-name prefix: "te-IN-Wavenet-A" → "te-IN". */
export function languageOfVoice(voice: string): string {
  const parts = voice.split("-");
  return parts.length >= 2 ? `${parts[0]}-${parts[1]}` : "te-IN";
}

export function cloudTtsConfigured(): boolean {
  return !!Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
}

// The API rejects anything over 5000 BYTES per request — not characters, which
// matters enormously here: Telugu is 3 bytes per character in UTF-8, so 5000
// bytes is only ~1,650 Telugu characters. Splitting on character count would
// pass in English testing and fail in production on the actual language.
// 4200 leaves headroom for the JSON envelope and multi-byte edge cases.
const MAX_REQUEST_BYTES = 4200;

const encoder = new TextEncoder();
const byteLen = (s: string) => encoder.encode(s).length;

/**
 * Split text into request-sized pieces, preferring sentence then word
 * boundaries so a break never lands mid-word (which the voice would render as
 * two clipped fragments).
 */
export function splitForRequests(text: string, maxBytes = MAX_REQUEST_BYTES): string[] {
  if (byteLen(text) <= maxBytes) return [text];

  // Telugu uses the Devanagari danda alongside Latin punctuation.
  const sentences = text.split(/(?<=[.!?।॥…])\s+/);
  const out: string[] = [];
  let current = "";

  const push = () => {
    if (current.trim()) out.push(current.trim());
    current = "";
  };

  for (const sentence of sentences) {
    if (byteLen(sentence) > maxBytes) {
      // A single sentence over the limit: fall back to word boundaries.
      push();
      let chunk = "";
      for (const word of sentence.split(/\s+/)) {
        const candidate = chunk ? `${chunk} ${word}` : word;
        if (byteLen(candidate) > maxBytes) {
          if (chunk) out.push(chunk);
          // A single "word" over the limit means text with no whitespace for
          // ~1,500+ characters — malformed OCR, not language. Sending it
          // unsliced is a guaranteed 400, so hard-slice it. Iterating code
          // points (not UTF-16 units) keeps surrogate pairs intact.
          if (byteLen(word) > maxBytes) {
            let piece = "";
            for (const cp of Array.from(word)) {
              if (byteLen(piece + cp) > maxBytes) {
                out.push(piece);
                piece = cp;
              } else {
                piece += cp;
              }
            }
            chunk = piece;
          } else {
            chunk = word;
          }
        } else {
          chunk = candidate;
        }
      }
      if (chunk) out.push(chunk);
      continue;
    }
    const candidate = current ? `${current} ${sentence}` : sentence;
    if (byteLen(candidate) > maxBytes) {
      push();
      current = sentence;
    } else {
      current = candidate;
    }
  }
  push();
  return out.filter(Boolean);
}

function base64ToBytes(b64: string): Uint8Array {
  const raw = atob(b64);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

async function synthesizeOne(
  text: string,
  voice: string,
  speakingRate: number,
): Promise<Uint8Array> {
  const token = await accessToken();
  const resp = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      input: { text },
      voice: { languageCode: languageOfVoice(voice), name: voice },
      audioConfig: { audioEncoding: "MP3", speakingRate },
    }),
    signal: AbortSignal.timeout(45_000),
  });

  if (!resp.ok) {
    const detail = await resp.text().catch(() => "");
    throw new Error(`cloud-tts HTTP ${resp.status}: ${detail.slice(0, 300)}`);
  }
  const data = await resp.json() as { audioContent?: string };
  if (!data.audioContent) throw new Error("cloud-tts returned no audioContent");
  return base64ToBytes(data.audioContent);
}

export interface CloudTtsResult {
  bytes: Uint8Array;
  /** Characters billed — what counts against the voice tier's free pool. */
  chars: number;
  voice: string;
  requests: number;
}

/**
 * Synthesise text to MP3.
 *
 * Splits over the byte limit and concatenates the resulting MP3s. Concatenating
 * MP3 frames is valid for playback: decoders resynchronise at the next frame
 * header. There can be a few milliseconds of silence at each seam, which is why
 * splitting prefers sentence boundaries — a pause where a full stop already is
 * sounds like reading, not like a glitch.
 */
export async function synthesize(
  text: string,
  voice: string,
  speakingRate = 1.0,
): Promise<CloudTtsResult> {
  const pieces = splitForRequests(text);
  const parts: Uint8Array[] = [];
  for (const piece of pieces) {
    parts.push(await synthesizeOne(piece, voice, speakingRate));
  }

  if (parts.length === 1) {
    return { bytes: parts[0], chars: text.length, voice, requests: 1 };
  }

  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return { bytes: out, chars: text.length, voice, requests: parts.length };
}

/**
 * Rough duration of an MP3, in seconds.
 *
 * Cloud TTS does not return a duration and parsing every frame header to get an
 * exact one is not worth it here: the value is used for progress display and
 * for the ledger, not for seeking. Assumes the constant bitrate the API
 * produces. Callers wanting precision should measure client-side once the
 * audio element has loaded.
 */
export function estimateMp3Seconds(bytes: number, kbps = 32): number {
  return Math.max(1, Math.round((bytes * 8) / (kbps * 1000)));
}
