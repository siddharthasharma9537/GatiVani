/**
 * Gemini 3.1 Flash TTS provider
 *
 * WHAT THIS TESTS:
 *   - Same input as 2.5 Flash TTS — direct quality comparison at 8× the cost
 *   - Audio tags: test case 04 (long paragraph) uses a [natural pace] tag
 *     to test whether style control is usable for newspaper narration
 *   - Whether the higher Elo score (1,211) is perceptible for Telugu content
 *
 * MODEL: gemini-3.1-flash-tts-preview
 * RELEASED: April 2026
 *
 * COST PER RUN (all 5 test cases, ~1,200 chars total):
 *   Input:  ~300 tokens  × $1.00/1M  = $0.0003
 *   Output: ~530s audio  × 25 tok/s  = 13,250 tokens × $20.00/1M = $0.265
 *   Total:  ~$0.265  for the full test suite  (vs $0.033 for Gemini 2.5)
 *
 * AUDIO TAGS (Gemini 3.1 only — natural language, not SSML):
 *   Wrap text segments with bracketed directives. Examples:
 *     [slow]    — reduce speaking pace
 *     [excited] — energetic delivery
 *     [calm]    — measured, relaxed tone
 *     [natural pace] — baseline; useful to explicitly reset after a tag
 *   Tags are stripped from the spoken output; they only affect prosody.
 */

import type { TTSResult } from "../types.ts";

const MODEL = "gemini-3.1-flash-tts-preview";
const BASE_URL = "https://generativelanguage.googleapis.com/v1beta";
const VOICE = "Kore"; // same voice as 2.5 test for fair comparison

// Pricing constants
const INPUT_PER_M_TOKEN = 1.00;
const OUTPUT_PER_M_TOKEN = 20.00;
const AUDIO_TOKENS_PER_SEC = 25;
const CHARS_PER_TOKEN = 4;

/**
 * Inject audio tags to demonstrate Gemini 3.1's style control.
 * For newspaper narration we keep it subtle — just [natural pace] to
 * verify the tag system works without distorting content.
 * Remove this wrapper to test plain-text parity with 2.5 Flash TTS.
 */
function withAudioTags(text: string, caseId: string): string {
  // Test case 04 (long paragraph) — demonstrate pace tag at article start
  if (caseId === "04_long_paragraph") {
    return `[natural pace] ${text}`;
  }
  // Test case 02 (code-switching) — test whether [clear] helps English words
  if (caseId === "02_code_switching") {
    return `[clear] ${text}`;
  }
  // All other cases: plain text, same as Gemini 2.5, for direct comparison
  return text;
}

export async function synthesizeGemini31(
  text: string,
  apiKey: string,
  caseId: string,
): Promise<TTSResult> {
  const taggedText = withAudioTags(text, caseId);
  const start = performance.now();

  const response = await fetch(
    `${BASE_URL}/models/${MODEL}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: taggedText }] }],
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
    throw new Error(`Gemini 3.1 Flash TTS error ${response.status}: ${err}`);
  }

  const data = await response.json();
  const part = data?.candidates?.[0]?.content?.parts?.[0];
  if (!part?.inlineData?.data) {
    throw new Error(`Gemini 3.1 Flash TTS: unexpected response shape — ${JSON.stringify(data).slice(0, 200)}`);
  }

  const audioB64: string = part.inlineData.data;
  const mimeType: string = part.inlineData.mimeType ?? "audio/wav";
  const audioBytes = Uint8Array.from(atob(audioB64), (c) => c.charCodeAt(0));
  const latencyMs = Math.round(performance.now() - start);

  const sampleRate = 24000;
  const durationSec = Math.round(audioBytes.length / (sampleRate * 2));

  const inputTokens = taggedText.length / CHARS_PER_TOKEN;
  const outputAudioTokens = durationSec * AUDIO_TOKENS_PER_SEC;
  const estimatedCostUsd =
    (inputTokens / 1_000_000) * INPUT_PER_M_TOKEN +
    (outputAudioTokens / 1_000_000) * OUTPUT_PER_M_TOKEN;

  return {
    provider: "Gemini 3.1 Flash TTS",
    audioBytes,
    mimeType,
    ext: mimeType.includes("mp3") ? "mp3" : "wav",
    latencyMs,
    durationSec,
    chunks: 1,
    inputChars: text.length,
    estimatedCostUsd: parseFloat(estimatedCostUsd.toFixed(5)),
    note: taggedText !== text ? `audio tags applied: "${taggedText.slice(0, 30)}…"` : undefined,
  };
}
