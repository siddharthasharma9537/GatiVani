// WAV (16-bit PCM) → MP3, for the Gemini TTS path.
//
// Why: Gemini TTS returns raw PCM, which we wrap in a WAV header and store as
// is. At 24 kHz mono that is ~2.9 MB per minute of speech — a 4-hour edition is
// ~700 MB. The audio bucket grew ~600 MB/month with no retention and eventually
// tripped the project's storage quota, at which point EVERY edge function
// started returning 402: a bucket of regenerable audio took down the news
// feeds. See docs/R2_AUDIO_MIGRATION.md and docs/ORCHESTRATION_PLAN.md §Phase 0.
//
// Measured on this encoder (10 s of 24 kHz mono, @breezystack/lamejs at 48 kbps):
//   0.46 MB WAV → 59 KB MP3   ≈ 8× smaller
//   364 ms to encode 10 s     ≈ 27× realtime
//
// That second number is why this is OFF by default. A typical article is 1–2
// minutes of speech, so encoding costs roughly 2–5 s of CPU inside the edge
// function. Supabase enforces a CPU-time budget per invocation separately from
// the 150 s wall clock, and it is not measurable from a dev machine. Enable
// with AUDIO_FORMAT=mp3 and watch for CPU-limit errors before making it the
// default.
//
// Phase 2 of the plan makes this mostly moot: Cloud TTS returns MP3 natively
// at zero CPU cost, so only the Gemini prewarm/fallback path needs encoding.

/** True when the function is configured to store MP3 instead of WAV. */
export function mp3Enabled(): boolean {
  return (Deno.env.get("AUDIO_FORMAT") ?? "wav").toLowerCase() === "mp3";
}

/**
 * Locate the PCM payload inside a RIFF/WAVE buffer.
 *
 * Not assuming a fixed 44-byte header: a header carrying a LIST/INFO chunk is
 * still valid WAV and would otherwise shift every sample by a few bytes and
 * turn the audio into noise. Walks the chunk table instead.
 */
function findDataChunk(wav: Uint8Array): { offset: number; length: number } | null {
  if (wav.length < 12) return null;
  const dv = new DataView(wav.buffer, wav.byteOffset, wav.byteLength);
  const tag = (o: number) =>
    String.fromCharCode(wav[o], wav[o + 1], wav[o + 2], wav[o + 3]);
  if (tag(0) !== "RIFF" || tag(8) !== "WAVE") return null;

  let pos = 12;
  while (pos + 8 <= wav.length) {
    const id = tag(pos);
    const size = dv.getUint32(pos + 4, true);
    const body = pos + 8;
    if (id === "data") {
      return { offset: body, length: Math.min(size, wav.length - body) };
    }
    pos = body + size + (size % 2); // chunks are word-aligned
  }
  return null;
}

/**
 * Encode 16-bit mono PCM to MP3.
 *
 * Returns null on any failure — a missing dependency, an unparseable header, an
 * encoder throw. Callers MUST fall back to storing the original WAV: shrinking
 * a file is an optimisation, and an optimisation may never be the reason a
 * narration fails to play.
 */
export async function wavToMp3(
  wavBytes: Uint8Array,
  sampleRate: number,
  bitrateKbps = 48,
): Promise<Uint8Array | null> {
  try {
    const data = findDataChunk(wavBytes);
    if (!data || data.length < 2) return null;

    // Int16Array needs 2-byte alignment, which the data chunk's offset into the
    // original buffer does not guarantee — copy rather than view.
    const pcmBytes = wavBytes.slice(data.offset, data.offset + (data.length & ~1));
    const pcm = new Int16Array(pcmBytes.buffer, pcmBytes.byteOffset, pcmBytes.length / 2);

    const lamejs = await import("npm:@breezystack/lamejs@1.2.7");
    const encoder = new lamejs.Mp3Encoder(1, sampleRate, bitrateKbps);

    const frames: Uint8Array[] = [];
    const BLOCK = 1152; // one MPEG frame's worth of samples
    for (let i = 0; i < pcm.length; i += BLOCK) {
      const buf = encoder.encodeBuffer(pcm.subarray(i, Math.min(i + BLOCK, pcm.length)));
      if (buf.length) frames.push(buf);
    }
    const tail = encoder.flush();
    if (tail.length) frames.push(tail);
    if (!frames.length) return null;

    const total = frames.reduce((n, f) => n + f.length, 0);
    const out = new Uint8Array(total);
    let at = 0;
    for (const f of frames) {
      out.set(f, at);
      at += f.length;
    }
    return out;
  } catch (e) {
    console.warn("[mp3] encode failed, keeping WAV:", (e as Error).message);
    return null;
  }
}

/**
 * Duration of a 16-bit mono WAV, in seconds.
 *
 * Must be measured on the PCM, before any encoding — an MP3's byte length says
 * nothing about its duration at a variable bitrate.
 */
export function wavDurationSeconds(wavBytes: Uint8Array, sampleRate: number): number {
  const data = findDataChunk(wavBytes);
  const bytes = data ? data.length : Math.max(0, wavBytes.length - 44);
  return Math.round(bytes / (sampleRate * 2));
}
