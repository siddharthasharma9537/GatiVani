/**
 * Sarvam Bulbul:v3 TTS provider
 *
 * WHAT THIS TESTS:
 *   - Real Bulbul:v3 output at 48kHz, speaker "shubh" (default GatiVani voice)
 *   - Chunking behaviour: text > 450 chars is split at sentence boundaries,
 *     each chunk sent separately, WAV PCM data concatenated
 *   - The join seam between chunks is intentionally audible on test case 04
 *     so you can judge whether it's acceptable in production
 *
 * COST PER RUN (all 5 test cases, ~1,200 chars total):
 *   ~₹1.80  (~$0.021)  at ₹15/10K chars
 */

import { SarvamAIClient } from "npm:sarvamai@1.1.7";
import type { TTSResult } from "../types.ts";

const CHUNK_LIMIT = 450;
const HEADER_BYTES = 44;

// Split at Telugu/Hindi sentence endings and common punctuation
function chunkText(text: string): string[] {
  if (text.length <= CHUNK_LIMIT) return [text];

  const chunks: string[] = [];
  const sentences = text.split(/(?<=[।॥|.!?\n])\s*/u).filter((s) => s.trim());
  let current = "";

  for (const sentence of sentences) {
    if (sentence.length > CHUNK_LIMIT) {
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
  return chunks.filter((c) => c.length > 0);
}

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function concatWav(buffers: Uint8Array[]): Uint8Array {
  if (buffers.length === 1) return buffers[0];
  const allPcm = buffers.map((b, i) => b.slice(i === 0 ? HEADER_BYTES : HEADER_BYTES));
  const pcmTotal = allPcm.reduce((s, p) => s + p.length, 0);
  const result = new Uint8Array(HEADER_BYTES + pcmTotal);
  result.set(buffers[0].slice(0, HEADER_BYTES), 0);
  let offset = HEADER_BYTES;
  for (const pcm of allPcm) { result.set(pcm, offset); offset += pcm.length; }
  const view = new DataView(result.buffer);
  view.setUint32(4, result.length - 8, true);   // RIFF chunk size
  view.setUint32(40, pcmTotal, true);            // data sub-chunk size
  return result;
}

export async function synthesizeSarvam(
  text: string,
  apiKey: string,
): Promise<TTSResult> {
  const client = new SarvamAIClient({ apiSubscriptionKey: apiKey });
  const chunks = chunkText(text);
  const wavBuffers: Uint8Array[] = [];
  const start = performance.now();

  for (const chunk of chunks) {
    const resp = await client.textToSpeech.convert({
      text: chunk,
      target_language_code: "te-IN",
      speaker: "shubh",
      pace: 1.1,
      speech_sample_rate: 48000,
      enable_preprocessing: true,
      model: "bulbul:v3",
    });
    const audioB64: string | null =
      resp?.audios?.length ? resp.audios[0] : typeof resp === "string" ? resp : null;
    if (!audioB64) throw new Error(`Sarvam returned no audio for chunk: "${chunk.slice(0, 40)}…"`);
    wavBuffers.push(b64ToBytes(audioB64));
  }

  const combined = concatWav(wavBuffers);
  const latencyMs = Math.round(performance.now() - start);
  const durationSec = Math.round(combined.length / (48000 * 2)); // 16-bit mono @ 48kHz
  const costUsd = (text.length / 10000) * (15 / 84);             // ₹15/10K chars at ₹84/$1

  return {
    provider: "Sarvam Bulbul:v3",
    audioBytes: combined,
    mimeType: "audio/wav",
    ext: "wav",
    latencyMs,
    durationSec,
    chunks: chunks.length,
    inputChars: text.length,
    estimatedCostUsd: parseFloat(costUsd.toFixed(5)),
  };
}
