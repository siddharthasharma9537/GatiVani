import { GoogleGenAI } from "@google/genai";
import { env } from "../config/env.js";

const apiKey = env.geminiApiKey;
if (!apiKey) {
  console.error("[gemini-service] Warning: GEMINI_API_KEY is not set in env.");
}

const ai = new GoogleGenAI({ apiKey });

/**
 * Sends text or a raw file buffer to Gemini and returns a Telugu broadcast script.
 *
 * Canonical name: services/gemini-service.js
 * (services/gemini.js is a backward-compat re-export)
 *
 * @param {{ text?: string; buffer?: Buffer; mimeType?: string; tier?: string }} params
 * @returns {Promise<string>} Telugu audio script
 */
export async function generateScript(params) {
  const { text, buffer, mimeType } = params;

  const systemInstruction = `
    You are an expert Telugu news broadcast script editor for GatiVani.
    Transform raw newspaper content into an audio-optimized conversational script.
    Rules:
    1. Read column text top-to-bottom sequentially. Do not merge separate columns horizontally.
    2. Convert symbols, numbers, and currency to spoken Telugu (e.g. '2026' → 'రెండు వేల ఇరవై ఆరు', '₹' → 'రూపాయలు').
    3. Fix scanning artifacts. Maintain a broadcast-quality style.
    4. Output ONLY the clean Telugu text. No English commentary or filler.
  `;

  const contents = [];

  if (text && text.trim().length > 0) {
    contents.push(text);
  } else if (buffer) {
    contents.push({
      inlineData: {
        data: buffer.toString("base64"),
        mimeType: mimeType || "application/pdf",
      },
    });
    contents.push(
      "Analyze this regional newspaper page. Extract column text top-to-bottom sequentially."
    );
  } else {
    throw new Error("generateScript: neither text nor buffer was provided.");
  }

  const response = await ai.models.generateContent({
    model: env.geminiModel,
    contents,
    config: { systemInstruction, temperature: 0.3 },
  });

  if (!response?.text) {
    throw new Error("Gemini returned an empty response.");
  }

  return response.text;
}

// Backward-compat alias — callers using generateWithGemini still work.
export const generateWithGemini = generateScript;
