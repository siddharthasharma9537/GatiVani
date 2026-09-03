// Google Cloud Text-to-Speech — the free lane.
//
// Why this exists: Gemini TTS bills every second of speech (~₹1.43/min), so a
// 3–4 hour edition costs more than ₹300 to narrate. Cloud TTS gives a monthly
// free pool per voice tier. For te-IN that is Standard 4M characters and
// Chirp 3 HD 1M — 5M free characters a month, or ~25 editions. Narration stops
// being the dominant cost line and becomes, in practice, free.
// See docs/ORCHESTRATION_PLAN.md §2.3.
//
// It also returns MP3 directly, so the free lane skips the CPU cost of the
// lamejs encode that the Gemini path needs (_shared/mp3.ts).

const ENDPOINT = "https://texttospeech.googleapis.com/v1/text:synthesize";

// Cloud TTS accepts API-key auth, so this needs no service account and no
// signed JWT — just the key, restricted to the Text-to-Speech API in the
// console. Verified end to end on 2026-09-03: voices.list and text:synthesize
// both return 200 with `?key=`.
function apiKey(): string {
  const k = Deno.env.get("GOOGLE_TTS_API_KEY");
  if (!k) throw new Error("GOOGLE_TTS_API_KEY is not set");
  return k;
}

/**
 * Which voice each surface speaks in.
 *
 * Pinned per surface rather than chosen dynamically: a pool draining mid-month
 * must never silently change the voice of a feed people hear every day.
 *
 * Telugu has exactly two tiers — Standard (A–D) and Chirp3-HD. There is no
 * WaveNet and no Neural2 for te-IN, confirmed against the voices API on
 * 2026-09-03, so the three-tier assignment this started as collapses to two.
 * Standard is $4/1M characters against a 4M free pool; Chirp3-HD is $30/1M
 * against a 1M pool, which is 7.5x the rate and a quarter of the headroom.
 *
 * So the heard-every-day surfaces sit on Standard, and Chirp3-HD is spent only
 * on the prewarmed top stories, where the volume is bounded. Whether the live
 * surfaces are worth upgrading is a question for `edition_cost` once it has
 * real numbers — the same discipline RASTER_PAGES is under.
 */
export const VOICE_BY_SURFACE: Record<string, string> = {
  // Most-heard surface. Standard because te-IN has no mid tier to promote to.
  live_article: "te-IN-Standard-A",
  // Falls back to the same voice as live_article so the ticker and the story
  // it opens never sound like two different narrators.
  live_ticker: "te-IN-Standard-A",
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

/** Language code is the voice-name prefix: "te-IN-Standard-A" → "te-IN". */
export function languageOfVoice(voice: string): string {
  const parts = voice.split("-");
  return parts.length >= 2 ? `${parts[0]}-${parts[1]}` : "te-IN";
}

export function cloudTtsConfigured(): boolean {
  return !!Deno.env.get("GOOGLE_TTS_API_KEY");
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
  const resp = await fetch(`${ENDPOINT}?key=${apiKey()}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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
 * The MP3 bitrate Cloud TTS actually encodes at, by voice tier — measured
 * with ffprobe against real output on 2026-09-03, not documented anywhere:
 * te-IN-Standard-A came back 64kbps, te-IN-Chirp3-HD-Achernar 32kbps. A
 * single assumed constant (32, the old default) was exactly right for one
 * tier and exactly double the truth for the other — which doesn't just
 * mis-report a number: the player's chunk-advance logic
 * (playback_service.dart) treats a completed chunk as genuine only when the
 * real audio element's duration is within 3s of this estimate, to reject
 * stale `completed` events left over from the previous chunk. Get the
 * bitrate wrong by 2x either direction and every real chunk fails that
 * check and is treated as stale — multi-chunk narration silently stopped at
 * the first chunk's real length (~40-55s) with the player still reporting
 * "playing". A player-side fix wasn't needed; this was the only wrong value,
 * and it needs to vary with the voice rather than default to either number.
 */
function mp3Kbps(voice: string): number {
  return voice.includes("Chirp3-HD") ? 32 : 64;
}

/**
 * Rough duration of an MP3, in seconds.
 *
 * Cloud TTS does not return a duration and parsing every frame header to get an
 * exact one is not worth it here: the value is used for progress display and
 * for the ledger, not for seeking. Callers wanting precision should measure
 * client-side once the audio element has loaded.
 */
export function estimateMp3Seconds(bytes: number, voice: string): number {
  return Math.max(1, Math.round((bytes * 8) / (mp3Kbps(voice) * 1000)));
}
