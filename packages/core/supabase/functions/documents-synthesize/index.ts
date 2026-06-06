import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { SarvamAIClient } from "npm:sarvamai@1.1.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-subscription-tier",
};

const LANGUAGE_CONFIG: Record<string, { code: string; sampleRate: number; speaker: string }> = {
  te: { code: "te-IN", sampleRate: 48000, speaker: "shubh" },
  hi: { code: "hi-IN", sampleRate: 22050, speaker: "tanya" },
  en: { code: "en-IN", sampleRate: 22050, speaker: "amit" },
};

const CHUNK_LIMIT = 450; // Sarvam Bulbul:v3 hard limit is 500 chars; stay under it

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Text chunking ──────────────────────────────────────────────────────────────
// Splits on sentence-ending punctuation (Telugu ।, ॥, |, \n, ., !, ?)
// so that chunks are always ≤ CHUNK_LIMIT characters.

function chunkText(text: string): string[] {
  if (text.length <= CHUNK_LIMIT) return [text];

  const chunks: string[] = [];
  // Split on sentence boundaries, keeping the delimiter
  const sentences = text.split(/(?<=[।॥|.!?\n])\s*/u).filter(s => s.trim());

  let current = "";
  for (const sentence of sentences) {
    if (sentence.length > CHUNK_LIMIT) {
      // Sentence itself is too long — split on word boundaries
      if (current.trim()) { chunks.push(current.trim()); current = ""; }
      const words = sentence.split(/\s+/);
      let part = "";
      for (const word of words) {
        if ((part + " " + word).length > CHUNK_LIMIT) {
          if (part.trim()) chunks.push(part.trim());
          part = word;
        } else {
          part = part ? part + " " + word : word;
        }
      }
      if (part.trim()) current = part.trim();
    } else if ((current + " " + sentence).length > CHUNK_LIMIT) {
      if (current.trim()) chunks.push(current.trim());
      current = sentence;
    } else {
      current = current ? current + " " + sentence : sentence;
    }
  }
  if (current.trim()) chunks.push(current.trim());
  return chunks.filter(c => c.length > 0);
}

// ── WAV concatenation ─────────────────────────────────────────────────────────
// Each Sarvam response is a 16-bit PCM WAV. We strip the 44-byte header on all
// chunks after the first, concatenate raw PCM, then update the size fields in
// the first header.

function concatWavBuffers(buffers: Uint8Array[]): Uint8Array {
  if (buffers.length === 1) return buffers[0];

  const HEADER = 44;
  // Collect PCM data from every buffer
  const pcmParts: Uint8Array[] = buffers.map((b, i) => b.slice(i === 0 ? 0 : HEADER));
  const totalLength = pcmParts.reduce((s, p) => s + p.length, 0);

  const out = new Uint8Array(HEADER + (totalLength - pcmParts[0].length) + pcmParts[0].length);
  // Actually simpler: keep first header, append all PCM (header from first, raw PCM from rest)
  const firstHeader = buffers[0].slice(0, HEADER);
  const allPcm = buffers.map((b, i) => b.slice(i === 0 ? HEADER : HEADER));
  const pcmTotal = allPcm.reduce((s, p) => s + p.length, 0);

  const result = new Uint8Array(HEADER + pcmTotal);
  result.set(firstHeader, 0);
  let offset = HEADER;
  for (const pcm of allPcm) {
    result.set(pcm, offset);
    offset += pcm.length;
  }

  // Update RIFF chunk size (bytes 4–7): total file size − 8
  const view = new DataView(result.buffer);
  view.setUint32(4, result.length - 8, true);
  // Update data sub-chunk size (bytes 40–43)
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

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const SARVAM = Deno.env.get("SARVAM_API_KEY");
    if (!SARVAM) return json({ error: "config_missing", message: "SARVAM_API_KEY not configured" }, 500);

    const body = await req.json().catch(() => null);
    if (!body || typeof body.text !== "string") {
      return json({ error: "missing_text", message: 'Expected "text" field in body.' }, 400);
    }
    const text = body.text.trim();
    if (!text) return json({ error: "empty_text", message: "Text cannot be empty." }, 400);

    const langKey = (body.language || "te-IN").split("-")[0];
    const cfg = LANGUAGE_CONFIG[langKey] || LANGUAGE_CONFIG.te;
    const speaker = body.speaker || cfg.speaker;

    const chunks = chunkText(text);
    console.log(`[synthesize] ${text.length} chars → ${chunks.length} chunk(s)`);

    const sarvam = new SarvamAIClient({ apiSubscriptionKey: SARVAM });
    const wavBuffers: Uint8Array[] = [];

    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      console.log(`[synthesize] chunk ${i + 1}/${chunks.length}: ${chunk.length} chars`);

      const resp = await sarvam.textToSpeech.convert({
        text: chunk,
        target_language_code: cfg.code,
        speaker,
        pace: 1.1,
        speech_sample_rate: cfg.sampleRate,
        enable_preprocessing: true,
        model: "bulbul:v3",
      });

      let audioB64: string | null = null;
      if (resp?.audios?.length) audioB64 = resp.audios[0];
      else if (typeof resp === "string") audioB64 = resp;

      if (!audioB64) {
        console.warn(`[synthesize] No audio for chunk ${i + 1}, skipping`);
        continue;
      }
      wavBuffers.push(base64ToBytes(audioB64));
    }

    if (wavBuffers.length === 0) {
      return json({ error: "synthesis_failed", message: "All chunks failed to synthesize" }, 500);
    }

    const combined = concatWavBuffers(wavBuffers);
    const combinedB64 = bytesToBase64(combined);
    const durationSec = Math.round(combined.length / (cfg.sampleRate * 2)); // 16-bit mono

    console.log(`[synthesize] combined: ${Math.round(combined.length / 1024)} KB, ~${durationSec}s`);

    return json({
      ok: true,
      audioUrl: `data:audio/mpeg;base64,${combinedB64}`,
      provider: "sarvam",
      language: langKey,
      speaker,
      chunks: chunks.length,
      durationSeconds: durationSec,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-synthesize]", err);
    return json({ error: "synthesis_failed", message }, 500);
  }
});
