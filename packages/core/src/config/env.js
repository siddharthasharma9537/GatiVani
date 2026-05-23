import dotenv from "dotenv";

dotenv.config();

function int(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) ? n : fallback;
}

function bool(name, fallback = false) {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  return ["1", "true", "yes", "on"].includes(String(raw).toLowerCase());
}

export const env = {
  port: int("PORT", 8788),
  nodeEnv: process.env.NODE_ENV || "development",
  geminiApiKey: process.env.GEMINI_API_KEY || "",
  geminiModel: process.env.GEMINI_MODEL || "gemini-2.5-flash",
  // Public-facing origin for building storageUrl in API responses.
  // Set in .env: PUBLIC_ORIGIN=https://gativani.sohum.cloud
  publicOrigin: process.env.PUBLIC_ORIGIN || "http://localhost:8788",
  tierMaxPages: {
    free: int("TIER_FREE_MAX_PAGES", 5),
    standard: int("TIER_STANDARD_MAX_PAGES", 50),
    premium: int("TIER_PREMIUM_MAX_PAGES", 500),
  },
  // Set to true in dev to accept X-Subscription-Tier from client headers.
  // In production keep false and verify via JWT / billing webhook instead.
  trustClientTierHeaders: bool("TRUST_CLIENT_TIER_HEADERS", false),
  // Azure Cognitive Services Speech (TTS)
  azureTtsKey: process.env.AZURE_TTS_KEY || "",
  azureTtsRegion: process.env.AZURE_TTS_REGION || "centralindia",
};

export function assertGeminiConfigured() {
  if (!env.geminiApiKey) {
    throw new Error("GEMINI_API_KEY is required to call Gemini.");
  }
}

export function assertAzureTtsConfigured() {
  if (!env.azureTtsKey) {
    throw new Error("AZURE_TTS_KEY is required for text-to-speech.");
  }
}
