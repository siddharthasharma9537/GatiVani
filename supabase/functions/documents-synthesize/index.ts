import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { SarvamAIClient } from "npm:sarvamai@1.1.7";
import { createClient } from "npm:@supabase/supabase-js@2";
import { alignAndStore } from "./alignment.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-subscription-tier",
};

// ── Language config ────────────────────────────────────────────────────────────

const LANGUAGE_CONFIG: Record<string, { code: string; sampleRate: number; speaker: string }> = {
  te: { code: "te-IN", sampleRate: 48000, speaker: "shubh" },
  hi: { code: "hi-IN", sampleRate: 22050, speaker: "tanya" },
  en: { code: "en-IN", sampleRate: 22050, speaker: "amit" },
};

// ── Tier → TTS provider routing ────────────────────────────────────────────────
// free / standard / premium   → Gemini 2.5 Flash TTS  (~8× cheaper, no chunking)
// super_premium+               → Sarvam Bulbul:v3     (best Telugu phonetics)

type TtsProvider = "gemini-2.5" | "sarvam";

const TIER_PROVIDER: Record<string, TtsProvider> = {
  free:                   "gemini-2.5",
  standard:               "gemini-2.5",
  premium:                "gemini-2.5",
  super_premium:          "sarvam",
  super_premium_advanced: "sarvam",
};

// ── Gemini voice mapping ───────────────────────────────────────────────────────
// Sarvam female voices → Kore (clear, warm female)
// Sarvam male voices   → Puck (natural male)

const FEMALE_SARVAM = new Set(["priya", "neha", "kavya", "shreya", "suhani", "kavitha"]);

function geminiVoice(speaker: string): string {
  return FEMALE_SARVAM.has(speaker.toLowerCase()) ? "Kore" : "Puck";
}

// ── Sarvam chunking ───────────────────────────────────────────────────────────
// Sarvam Bulbul:v3 hard limit is 500 chars; stay safely under it.

const SARVAM_CHUNK_LIMIT = 450;

function chunkText(text: string): string[] {
  if (text.length <= SARVAM_CHUNK_LIMIT) return [text];
  const chunks: string[] = [];
  const sentences = text.split(/(?<=[।॥|.!?\n])\s*/u).filter(s => s.trim());
  let current = "";
  for (const sentence of sentences) {
    if (sentence.length > SARVAM_CHUNK_LIMIT) {
      if (current.trim()) { chunks.push(current.trim()); current = ""; }
      const words = sentence.split(/\s+/);
      let part = "";
      for (const word of words) {
        if ((part + " " + word).length > SARVAM_CHUNK_LIMIT) {
          if (part.trim()) chunks.push(part.trim());
          part = word;
        } else {
          part = part ? part + " " + word : word;
        }
      }
      if (part.trim()) current = part.trim();
    } else if ((current + " " + sentence).length > SARVAM_CHUNK_LIMIT) {
      if (current.trim()) chunks.push(current.trim());
      current = sentence;
    } else {
      current = current ? current + " " + sentence : sentence;
    }
  }
  if (current.trim()) chunks.push(current.trim());
  return chunks.filter(c => c.length > 0);
}

// ── WAV utilities ─────────────────────────────────────────────────────────────

function buildWavHeader(
  pcmByteLength: number,
  sampleRate: number,
  channels = 1,
  bitsPerSample = 16,
): Uint8Array {
  const header = new Uint8Array(44);
  const view = new DataView(header.buffer);
  const byteRate = sampleRate * channels * (bitsPerSample / 8);
  const blockAlign = channels * (bitsPerSample / 8);

  header.set([0x52, 0x49, 0x46, 0x46], 0); // "RIFF"
  view.setUint32(4, 36 + pcmByteLength, true);
  header.set([0x57, 0x41, 0x56, 0x45], 8); // "WAVE"
  header.set([0x66, 0x6d, 0x74, 0x20], 12); // "fmt "
  view.setUint32(16, 16, true);    // chunk size
  view.setUint16(20, 1, true);     // PCM
  view.setUint16(22, channels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);
  header.set([0x64, 0x61, 0x74, 0x61], 36); // "data"
  view.setUint32(40, pcmByteLength, true);
  return header;
}

function concatWavBuffers(buffers: Uint8Array[]): Uint8Array {
  if (buffers.length === 1) return buffers[0];
  const HEADER = 44;
  const firstHeader = buffers[0].slice(0, HEADER);
  const allPcm = buffers.map(b => b.slice(HEADER));
  const pcmTotal = allPcm.reduce((s, p) => s + p.length, 0);
  const result = new Uint8Array(HEADER + pcmTotal);
  result.set(firstHeader, 0);
  let offset = HEADER;
  for (const pcm of allPcm) { result.set(pcm, offset); offset += pcm.length; }
  const view = new DataView(result.buffer);
  view.setUint32(4, result.length - 8, true);
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

// ── Reading-style prompt wrapper ──────────────────────────────────────────────

function styledText(text: string, readingStyle?: string): string {
  switch (readingStyle) {
    case "news_anchor":
      return `Read the following as a professional Telugu news anchor. Speak clearly and at an engaging pace:\n\n${text}`;
    case "devotional_slow":
      return `Read the following devotional content with reverence and calm. Speak slowly and clearly, pausing naturally between sentences:\n\n${text}`;
    case "mantra_clear":
      return `Read the following Sanskrit text very slowly and clearly. Pronounce each syllable distinctly with proper pausing between words:\n\n${text}`;
    default:
      return text;
  }
}

// ── Gemini 2.5 Flash TTS ──────────────────────────────────────────────────────
// Returns raw PCM int16 LE at 24 kHz mono — no chunking needed.

async function synthesizeWithGemini(
  text: string,
  speaker: string,
  geminiKey: string,
  readingStyle?: string,
): Promise<{ wavBytes: Uint8Array; durationSec: number; chunks: number }> {
  const voiceName = geminiVoice(speaker);
  const GEMINI_SAMPLE_RATE = 24000;
  // Gemini TTS works best with natural content — don't inject English instructions
  // into Telugu text. Style is handled via Sarvam pace instead.
  const ttsInput = text;

  console.log(`[gemini-tts] ${text.length} chars, voice=${voiceName}, style=${readingStyle ?? "default"}`);

  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=${geminiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: ttsInput }] }],
        generationConfig: {
          responseModalities: ["AUDIO"],
          speechConfig: {
            voiceConfig: {
              prebuiltVoiceConfig: { voiceName },
            },
          },
        },
      }),
    },
  );

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Gemini TTS HTTP ${resp.status}: ${errText.slice(0, 200)}`);
  }

  const data = await resp.json() as {
    candidates?: Array<{
      content?: { parts?: Array<{ inlineData?: { data?: string } }> };
    }>;
  };

  const rawB64 = data?.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data;
  if (!rawB64) throw new Error("Gemini TTS: no audio data in response");

  const pcmBytes = base64ToBytes(rawB64);
  const header = buildWavHeader(pcmBytes.length, GEMINI_SAMPLE_RATE);
  const wavBytes = new Uint8Array(44 + pcmBytes.length);
  wavBytes.set(header, 0);
  wavBytes.set(pcmBytes, 44);

  const durationSec = Math.round(pcmBytes.length / (GEMINI_SAMPLE_RATE * 2));
  return { wavBytes, durationSec, chunks: 1 };
}

// ── Sarvam Bulbul:v3 TTS ──────────────────────────────────────────────────────

async function synthesizeWithSarvam(
  text: string,
  speaker: string,
  langCode: string,
  sampleRate: number,
  sarvamKey: string,
  readingStyle?: string,
): Promise<{ wavBytes: Uint8Array; durationSec: number; chunks: number }> {
  const pace = readingStyle === "devotional_slow" ? 0.85
    : readingStyle === "mantra_clear" ? 0.75
    : 1.1;
  const sarvam = new SarvamAIClient({ apiSubscriptionKey: sarvamKey });
  const chunks = chunkText(text);
  console.log(`[sarvam-tts] ${text.length} chars → ${chunks.length} chunk(s), voice=${speaker}`);

  const wavBuffers: Uint8Array[] = [];
  for (let i = 0; i < chunks.length; i++) {
    const chunk = chunks[i];
    console.log(`[sarvam-tts] chunk ${i + 1}/${chunks.length}: ${chunk.length} chars`);
    const resp = await sarvam.textToSpeech.convert({
      text: chunk,
      target_language_code: langCode,
      speaker,
      pace,
      speech_sample_rate: sampleRate,
      enable_preprocessing: true,
      model: "bulbul:v3",
    });

    let audioB64: string | null = null;
    if (resp?.audios?.length) audioB64 = resp.audios[0];
    else if (typeof resp === "string") audioB64 = resp;
    if (!audioB64) { console.warn(`[sarvam-tts] no audio chunk ${i + 1}, skipping`); continue; }
    wavBuffers.push(base64ToBytes(audioB64));
  }

  if (wavBuffers.length === 0) throw new Error("All Sarvam chunks failed to synthesize");

  const combined = concatWavBuffers(wavBuffers);
  const durationSec = Math.round(combined.length / (sampleRate * 2));
  return { wavBytes: combined, durationSec, chunks: chunks.length };
}

// ── Response helper ───────────────────────────────────────────────────────────

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const SARVAM_KEY = Deno.env.get("SARVAM_API_KEY");
    const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY");

    const body = await req.json().catch(() => null);
    if (!body || typeof body.text !== "string") {
      return json({ error: "missing_text", message: 'Expected "text" field in body.' }, 400);
    }
    const text = body.text.trim();
    if (!text) return json({ error: "empty_text", message: "Text cannot be empty." }, 400);

    const langKey = (body.language || "te-IN").split("-")[0];
    const cfg = LANGUAGE_CONFIG[langKey] ?? LANGUAGE_CONFIG.te;
    const speaker = (body.speaker as string | undefined) || cfg.speaker;
    const readingStyle = (body.readingStyle as string | undefined) || undefined;

    // Optional audio cache: pass the article's DB uuid ("articleId") and the
    // generated audio is stored once in the public "audio" bucket and reused on
    // every later call — TTS is the dominant pipeline cost (~85%).
    const articleId = typeof body.articleId === "string" && body.articleId ? body.articleId : "";
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabase = (articleId && SUPABASE_URL && SERVICE_KEY)
      ? createClient(SUPABASE_URL, SERVICE_KEY)
      : null;

    if (supabase) {
      const { data: row } = await supabase
        .from("articles").select("audio_url").eq("id", articleId).maybeSingle();
      if (row?.audio_url) {
        console.log(`[synthesize] cache hit for article ${articleId}`);
        return json({
          ok: true,
          audioUrl: row.audio_url,
          // word-level timings live next to the audio; the app falls back to
          // estimation if this 404s (alignment may still be running)
          timingsUrl: row.audio_url.replace(/\.wav$/, ".timings.json"),
          provider: "cache",
          language: langKey,
          speaker,
          chunks: 0,
          durationSeconds: null,
          cached: true,
        });
      }
    }

    // Determine provider from tier header; default "free" → Gemini 2.5
    const tier = (req.headers.get("x-subscription-tier") || "free").toLowerCase();
    const desiredProvider: TtsProvider = TIER_PROVIDER[tier] ?? "gemini-2.5";

    // Graceful fallback if a key is missing
    const effectiveProvider: TtsProvider =
      desiredProvider === "gemini-2.5" && !GEMINI_KEY ? "sarvam"
      : desiredProvider === "sarvam" && !SARVAM_KEY ? "gemini-2.5"
      : desiredProvider;

    if (effectiveProvider === "gemini-2.5" && !GEMINI_KEY) {
      return json({ error: "config_missing", message: "GEMINI_API_KEY not configured" }, 500);
    }
    if (effectiveProvider === "sarvam" && !SARVAM_KEY) {
      return json({ error: "config_missing", message: "SARVAM_API_KEY not configured" }, 500);
    }

    console.log(`[synthesize] tier=${tier} provider=${effectiveProvider} chars=${text.length} speaker=${speaker}`);

    let wavBytes: Uint8Array;
    let durationSec: number;
    let chunks: number;
    let usedProvider = effectiveProvider;

    if (effectiveProvider === "gemini-2.5") {
      try {
        ({ wavBytes, durationSec, chunks } = await synthesizeWithGemini(text, speaker, GEMINI_KEY!, readingStyle));
      } catch (geminiErr) {
        const errMsg = geminiErr instanceof Error ? geminiErr.message : String(geminiErr);
        console.warn(`[synthesize] Gemini failed: ${errMsg.slice(0, 100)}`);

        // Fall back to Sarvam if available (handles rate limits, content blocks, quota exhaustion)
        if (SARVAM_KEY) {
          console.log("[synthesize] Falling back to Sarvam TTS");
          usedProvider = "sarvam";
          ({ wavBytes, durationSec, chunks } = await synthesizeWithSarvam(
            text, speaker, cfg.code, cfg.sampleRate, SARVAM_KEY, readingStyle,
          ));
        } else {
          throw geminiErr;
        }
      }
    } else {
      ({ wavBytes, durationSec, chunks } = await synthesizeWithSarvam(
        text, speaker, cfg.code, cfg.sampleRate, SARVAM_KEY!, readingStyle,
      ));
    }

    console.log(`[synthesize] done: ${Math.round(wavBytes.length / 1024)} KB ~${durationSec}s via ${usedProvider}`);

    // Persist to the public audio bucket + articles.audio_url for reuse.
    // The app accepts both plain URLs and data: URIs in audioUrl.
    let audioUrl = "";
    let timingsUrl = "";
    if (supabase) {
      const path = `articles/${articleId}.wav`;
      const { error: upErr } = await supabase.storage
        .from("audio")
        .upload(path, wavBytes, { contentType: "audio/wav", upsert: true });
      if (upErr) {
        console.warn("[synthesize] audio upload failed:", upErr.message);
      } else {
        audioUrl = supabase.storage.from("audio").getPublicUrl(path).data.publicUrl;
        timingsUrl = audioUrl.replace(/\.wav$/, ".timings.json");
        const { error: updErr } = await supabase
          .from("articles").update({ audio_url: audioUrl }).eq("id", articleId);
        if (updErr) console.warn("[synthesize] audio_url update failed:", updErr.message);

        // Background forced alignment (Sarvam STT with word timestamps) for
        // lyrics-style highlighting. Non-blocking: response returns now, the
        // timings file appears next to the audio ~30-90s later.
        if (SARVAM_KEY) {
          // deno-lint-ignore no-explicit-any
          (globalThis as any).EdgeRuntime?.waitUntil?.(alignAndStore({
            wavBytes,
            articleId,
            languageCode: body.language || "te-IN",
            sarvamKey: SARVAM_KEY,
            supabase,
          }));
        }
      }
    }
    if (!audioUrl) audioUrl = `data:audio/wav;base64,${bytesToBase64(wavBytes)}`;

    return json({
      ok: true,
      audioUrl,
      timingsUrl: timingsUrl || null,
      provider: usedProvider,
      language: langKey,
      speaker,
      chunks,
      durationSeconds: durationSec,
      cached: false,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-synthesize]", err);
    return json({ error: "synthesis_failed", message }, 500);
  }
});
