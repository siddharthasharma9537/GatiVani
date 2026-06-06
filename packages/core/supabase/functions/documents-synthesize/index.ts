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

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

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

    const sarvam = new SarvamAIClient({ apiSubscriptionKey: SARVAM });
    const resp = await sarvam.textToSpeech.convert({
      text,
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
    if (!audioB64) return json({ error: "synthesis_failed", message: "No audio returned" }, 500);

    return json({
      ok: true,
      audioUrl: `data:audio/mpeg;base64,${audioB64}`,
      provider: "sarvam",
      language: langKey,
      speaker,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-synthesize]", err);
    return json({ error: "synthesis_failed", message }, 500);
  }
});
