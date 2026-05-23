import { env, assertAzureTtsConfigured } from "../config/env.js";

/**
 * Generate natural Telugu audio using Microsoft Azure Cognitive Services Speech (REST API)
 * Returns audio data as a Buffer
 */
export async function generateTeluguAudio(text, language = "te-IN") {
  assertAzureTtsConfigured();

  const voiceMap = {
    "te-IN": "te-IN-ShrutiNeural",  // Natural female voice for Telugu
    "hi-IN": "hi-IN-SwaraNeural",   // Natural female voice for Hindi (when available)
    "en-IN": "en-IN-NeerjaNeural",  // Natural female voice for English (India)
  };

  const voice = voiceMap[language] || voiceMap["te-IN"];

  // Build SSML for natural prosody
  const ssml = `
    <speak version="1.0" xml:lang="${language}">
      <voice name="${voice}">
        <prosody rate="1.0" pitch="0%">
          ${escapeXml(text)}
        </prosody>
      </voice>
    </speak>
  `.trim();

  const url = `https://${env.azureTtsRegion}.tts.speech.microsoft.com/cognitiveservices/v1`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Ocp-Apim-Subscription-Key": env.azureTtsKey,
      "Content-Type": "application/ssml+xml",
      "X-Microsoft-OutputFormat": "audio-16khz-32kbitrate-mono-mp3",
    },
    body: ssml,
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`[Azure TTS] HTTP ${response.status}:`, {
      body: errorText,
      headers: Object.fromEntries(response.headers),
      ssml: ssml.substring(0, 200),
    });
    throw new Error(
      `Azure TTS error: ${response.status} - ${errorText || 'No error details'}`
    );
  }

  return Buffer.from(await response.arrayBuffer());
}

/**
 * Generate Telugu audio and return as base64-encoded data URL for use in frontend
 */
export async function generateTeluguAudioDataUrl(text, language = "te-IN") {
  const audioBuffer = await generateTeluguAudio(text, language);
  const base64Audio = audioBuffer.toString("base64");
  return `data:audio/mpeg;base64,${base64Audio}`;
}

/**
 * Escape special XML characters in text for SSML safety
 */
function escapeXml(text) {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}
