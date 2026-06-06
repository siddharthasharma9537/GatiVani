import dotenv from "dotenv";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.resolve(__dirname, "../../.env") });

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
  publicOrigin: process.env.PUBLIC_ORIGIN || "http://localhost:8788",
  tierMaxPages: {
    free: int("TIER_FREE_MAX_PAGES", 5),
    standard: int("TIER_STANDARD_MAX_PAGES", 50),
    premium: int("TIER_PREMIUM_MAX_PAGES", 500),
  },
  // In dev only — accepts X-Subscription-Tier from client headers.
  // Keep false in production and verify via JWT / billing webhook.
  trustClientTierHeaders: bool("TRUST_CLIENT_TIER_HEADERS", false),
  sarvamApiKey: process.env.SARVAM_API_KEY || "",
  supabaseUrl: process.env.SUPABASE_URL || "",
  supabaseAnonKey: process.env.SUPABASE_ANON_KEY || "",
};

export function assertSarvamConfigured() {
  if (!env.sarvamApiKey) {
    throw new Error("SARVAM_API_KEY is required.");
  }
}
