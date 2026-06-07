/**
 * Gemini 2.5 Flash TTS provider
 *
 * WHAT THIS TESTS:
 *   - Single-call synthesis (no chunking, no 500-char limit)
 *   - Telugu quality at the lowest Google TTS price point
 *   - Latency advantage over Sarvam (no async pipeline, no chunking loop)
 *
 * MODEL: gemini-2.5-flash-preview-tts
 * API:   generativelanguage.googleapis.com/v1beta
 *
 * COST PER RUN (all 5 test cases, ~1,200 chars total):
 *   Input:  ~300 tokens  × $0.30/1M  = $0.00009
 *   Output: ~530s audio  × 25 tok/s  = 13,250 tokens × $2.50/1M = $0.033
 *   Total:  ~$0.033  for the full test suite
 *
 * VOICE: "Kore" — closest neutral voice to Indian cadence available in 2.5 Flash TTS.
 *   Other options to try: "Aoede", "Charon", "Fenrir", "Puck".
 */

import type { TTSResult } from "../types.ts";

const MODEL = "gemini-2.5-flash-preview-tts";
const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";
const VOICE = "Kore";

// Pricing constants
const INPUT_PER_M_TOKEN = 0.30;
const OUTPUT_PER_M_TOKEN = 2.50;
const AUDIO_TOKENS_PER_SEC = 25;
const CHARS_PER_TOKEN = 4;

export async function synthesizeGemini25(
  text: string,
  apiKey: string,
): Promise<TTSResult> {
  const start = performance.now();

  const response = await fetch(
    `${BASE_URL}/models/${MODEL}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text }] }],
        generationConfig: {
          responseModalities: ["AUDIO"],
          speechConfig: {
            voiceConfig: { prebuiltVoiceConfig: { voiceName: VOICE } },
          },
        },
      }),
    },
  );

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Gemini 2.5 Flash TTS error ${response.status}: ${err}`);
  }

  const data = await response.json();
  const part = data?.candidates?.[0]?.content?.parts?.[0];
  if (!part?.inlineData?.data) {
    throw new Error(`Gemini 2.5 Flash TTS: unexpected response shape — ${JSON.stringify(data).slice(0, 200)}`);
  }

  const audioB64: string = part.inlineData.data;
  const mimeType: string = part.inlineData.mimeType ?? "audio/wav";
  const audioBytes = Uint8Array.from(atob(audioB64), (c) => c.charCodeAt(0));
  const latencyMs = Math.round(performance.now() - start);

  // Duration estimate from file size (16-bit PCM, sample rate varies; use 24kHz as Gemini default)
  const sampleRate = 24000;
  const durationSec = Math.round(audioBytes.length / (sampleRate * 2));

  // Cost estimate
  const inputTokens = text.length / CHARS_PER_TOKEN;
  const outputAudioTokens = durationSec * AUDIO_TOKENS_PER_SEC;
  const estimatedCostUsd =
    (inputTokens / 1_000_000) * INPUT_PER_M_TOKEN +
    (outputAudioTokens / 1_000_000) * OUTPUT_PER_M_TOKEN;

  return {
    provider: "Gemini 2.5 Flash TTS",
    audioBytes,
    mimeType,
    ext: mimeType.includes("mp3") ? "mp3" : "wav",
    latencyMs,
    durationSec,
    chunks: 1, // always 1 — no chunking needed
    inputChars: text.length,
    estimatedCostUsd: parseFloat(estimatedCostUsd.toFixed(5)),
  };
}
