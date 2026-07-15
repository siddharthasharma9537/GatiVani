import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
// Sarvam STT forced-alignment (./alignment.ts) is disabled for cost — see the
// commented-out alignAndStore call in the handler.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-subscription-tier, x-user-gemini-key",
};

// ── Language config ────────────────────────────────────────────────────────────

const LANGUAGE_CONFIG: Record<string, { code: string; sampleRate: number; speaker: string }> = {
  te: { code: "te-IN", sampleRate: 48000, speaker: "shubh" },
  hi: { code: "hi-IN", sampleRate: 22050, speaker: "tanya" },
  en: { code: "en-IN", sampleRate: 22050, speaker: "amit" },
};

// ── TTS provider ────────────────────────────────────────────────────────────────
// Gemini 2.5 Flash TTS for every tier. Sarvam TTS was removed (cost) — see the
// main handler; there is no Sarvam TTS fallback.

// ── Gemini voice mapping ───────────────────────────────────────────────────────
// Sarvam female voices → Kore (clear, warm female)
// Sarvam male voices   → Puck (natural male)

// Includes the Hindi default speaker ("tanya") alongside the Telugu names —
// this set is really "known female voice names across languages", not
// Telugu-only, despite its name.
const FEMALE_SARVAM = new Set(["priya", "neha", "kavya", "shreya", "suhani", "kavitha", "tanya"]);

function geminiVoice(speaker: string): string {
  return FEMALE_SARVAM.has(speaker.toLowerCase()) ? "Kore" : "Puck";
}

// ── Sarvam chunking ───────────────────────────────────────────────────────────
// Sarvam Bulbul:v3 hard limit is 500 chars; stay safely under it.

const SARVAM_CHUNK_LIMIT = 450;
// Per-chunk size for Gemini TTS. Gemini handles ~1.5k chars per call in ~75s
// and truncates well past that, so longer articles are split into chunks that
// are synthesized in parallel and stitched. Parallelism only pays off if the
// Gemini API rate limit is high enough for concurrent calls — otherwise they
// serialize and blow the function's ~150s wall clock (→ 504).
const GEMINI_CHUNK_LIMIT = 1450;

function chunkText(text: string, limit: number = SARVAM_CHUNK_LIMIT): string[] {
  if (text.length <= limit) return [text];
  const chunks: string[] = [];
  const sentences = text.split(/(?<=[।॥|.!?\n])\s*/u).filter(s => s.trim());
  let current = "";
  for (const sentence of sentences) {
    if (sentence.length > limit) {
      if (current.trim()) { chunks.push(current.trim()); current = ""; }
      const words = sentence.split(/\s+/);
      let part = "";
      for (const word of words) {
        if ((part + " " + word).length > limit) {
          if (part.trim()) chunks.push(part.trim());
          part = word;
        } else {
          part = part ? part + " " + word : word;
        }
      }
      if (part.trim()) current = part.trim();
    } else if ((current + " " + sentence).length > limit) {
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

const GEMINI_SAMPLE_RATE = 24000;

// One Gemini TTS call → a complete WAV for the given text.
async function geminiOneCall(
  text: string,
  voiceName: string,
  geminiKey: string,
): Promise<Uint8Array> {
  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=${geminiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text }] }],
        generationConfig: {
          responseModalities: ["AUDIO"],
          speechConfig: {
            voiceConfig: { prebuiltVoiceConfig: { voiceName } },
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
  return wavBytes;
}

async function synthesizeWithGemini(
  text: string,
  speaker: string,
  geminiKey: string,
  readingStyle?: string,
): Promise<{ wavBytes: Uint8Array; durationSec: number; chunks: number }> {
  const voiceName = geminiVoice(speaker);
  // Gemini works best with natural content — don't inject English instructions
  // into Telugu text. Style is handled via Sarvam pace instead.
  const parts = chunkText(text, GEMINI_CHUNK_LIMIT);
  console.log(
    `[gemini-tts] ${text.length} chars → ${parts.length} chunk(s), voice=${voiceName}, style=${readingStyle ?? "default"}`,
  );

  // Try Gemini for every article. Chunks run fully in parallel so wall time ≈
  // one chunk (~75s), not the sum — provided the API rate limit allows real
  // concurrency. If a chunk rejects it fails the attempt fast, leaving time for
  // the Sarvam fallback within the function wall clock.
  const wavs = await Promise.all(
    parts.map((p) => geminiOneCall(p, voiceName, geminiKey)),
  );
  const wavBytes = concatWavBuffers(wavs);
  const durationSec = Math.round((wavBytes.length - 44) / (GEMINI_SAMPLE_RATE * 2));
  return { wavBytes, durationSec, chunks: parts.length };
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
    // Which cached audio this is: the full article ("audio_url", default) or the
    // short briefing/summary narration ("summary_audio_url"). They cache to
    // separate columns + storage paths so a brief and a full clip never collide.
    const target = body.target === "summary_audio_url"
      ? "summary_audio_url"
      : "audio_url";
    const fileSuffix = target === "summary_audio_url" ? ".brief.wav" : ".wav";
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabase = (articleId && SUPABASE_URL && SERVICE_KEY)
      ? createClient(SUPABASE_URL, SERVICE_KEY)
      : null;

    if (supabase) {
      const { data: row } = await supabase
        .from("articles").select(target).eq("id", articleId).maybeSingle();
      const cachedUrl = (row as Record<string, string> | null)?.[target];
      if (cachedUrl) {
        console.log(`[synthesize] cache hit (${target}) for article ${articleId}`);
        return json({
          ok: true,
          audioUrl: cachedUrl,
          // word-level timings live next to the audio; the app falls back to
          // estimation if this 404s (alignment may still be running)
          timingsUrl: cachedUrl.replace(/\.wav$/, ".timings.json"),
          provider: "cache",
          language: langKey,
          speaker,
          chunks: 0,
          durationSeconds: null,
          cached: true,
        });
      }
    }

    // ── Chunk mode: return ONE synthesized chunk instead of waiting for the
    // whole article, so playback can start immediately. Chunking is
    // deterministic (same text + GEMINI_CHUNK_LIMIT always splits the same
    // way), so a chunk index is directly addressable — no job/session state
    // needed. Cached per (articleId, target, chunkIndex) in article_chunks,
    // same idea as the full-file cache above.
    const chunkIndex = typeof body.chunkIndex === "number" &&
        Number.isInteger(body.chunkIndex) && body.chunkIndex >= 0
      ? body.chunkIndex as number
      : null;
    if (chunkIndex !== null) {
      const parts = chunkText(text, GEMINI_CHUNK_LIMIT);
      if (chunkIndex >= parts.length) {
        return json({
          error: "chunk_out_of_range",
          message: `Only ${parts.length} chunk(s) available.`,
        }, 400);
      }

      if (supabase) {
        const { data: cached } = await supabase
          .from("article_chunks")
          .select("audio_url, duration_seconds")
          .eq("article_id", articleId).eq("target", target)
          .eq("chunk_index", chunkIndex).maybeSingle();
        if (cached?.audio_url) {
          console.log(`[synthesize] chunk cache hit ${chunkIndex} for ${articleId}`);
          return json({
            ok: true,
            audioUrl: cached.audio_url,
            durationSeconds: cached.duration_seconds,
            chunkIndex,
            totalChunks: parts.length,
            cached: true,
          });
        }
      }

      const geminiKey = req.headers.get("x-user-gemini-key") ?? "";
      if (!geminiKey) {
        return json({
          error: "gemini_key_required",
          message: "Add your Gemini API key to narrate this.",
        }, 400);
      }

      const wavBytes = await geminiOneCall(parts[chunkIndex], geminiVoice(speaker), geminiKey);
      const durationSec = Math.round((wavBytes.length - 44) / (GEMINI_SAMPLE_RATE * 2));
      console.log(`[synthesize] chunk ${chunkIndex}/${parts.length - 1} for ${articleId || "(no id)"}: ~${durationSec}s`);

      let audioUrl = "";
      if (supabase && articleId) {
        const base = fileSuffix.replace(/\.wav$/, ""); // "" or ".brief"
        const path = `articles/${articleId}${base}.chunk${chunkIndex}.wav`;
        const { error: upErr } = await supabase.storage
          .from("audio")
          .upload(path, wavBytes, { contentType: "audio/wav", upsert: true });
        if (upErr) {
          console.warn("[synthesize] chunk upload failed:", upErr.message);
        } else {
          audioUrl = supabase.storage.from("audio").getPublicUrl(path).data.publicUrl;
          const { error: cacheErr } = await supabase.from("article_chunks").upsert({
            article_id: articleId,
            target,
            chunk_index: chunkIndex,
            audio_url: audioUrl,
            duration_seconds: durationSec,
          }, { onConflict: "article_id,target,chunk_index" });
          if (cacheErr) console.warn("[synthesize] chunk cache write failed:", cacheErr.message);
        }
      }
      if (!audioUrl) audioUrl = `data:audio/wav;base64,${bytesToBase64(wavBytes)}`;

      return json({
        ok: true,
        audioUrl,
        durationSeconds: durationSec,
        chunkIndex,
        totalChunks: parts.length,
        cached: false,
      });
    }

    // TTS is Gemini 2.5 Flash ONLY, and always runs on the CALLER's own key —
    // there is no shared fallback anymore for any narration, Live or Paper
    // (the app now requires sign-in + BYOK before any playback). Sarvam TTS
    // remains disabled (cost) with no fallback either.
    const geminiKey = req.headers.get("x-user-gemini-key") ?? "";
    if (!geminiKey) {
      return json({
        error: "gemini_key_required",
        message: "Add your Gemini API key to narrate this.",
      }, 400);
    }

    console.log(`[synthesize] provider=gemini-2.5 chars=${text.length} speaker=${speaker}`);

    const usedProvider = "gemini-2.5";
    const { wavBytes, durationSec, chunks } =
      await synthesizeWithGemini(text, speaker, geminiKey, readingStyle);

    console.log(`[synthesize] done: ${Math.round(wavBytes.length / 1024)} KB ~${durationSec}s via ${usedProvider}`);

    // Persist to the public audio bucket + articles.audio_url for reuse.
    // The app accepts both plain URLs and data: URIs in audioUrl.
    let audioUrl = "";
    let timingsUrl = "";
    if (supabase) {
      const path = `articles/${articleId}${fileSuffix}`;
      const { error: upErr } = await supabase.storage
        .from("audio")
        .upload(path, wavBytes, { contentType: "audio/wav", upsert: true });
      if (upErr) {
        console.warn("[synthesize] audio upload failed:", upErr.message);
      } else {
        audioUrl = supabase.storage.from("audio").getPublicUrl(path).data.publicUrl;
        timingsUrl = audioUrl.replace(/\.wav$/, ".timings.json");
        const { error: updErr } = await supabase
          .from("articles").update({ [target]: audioUrl }).eq("id", articleId);
        if (updErr) console.warn(`[synthesize] ${target} update failed:`, updErr.message);

        // Forced alignment (Sarvam STT word timestamps) for lyric highlighting
        // is DISABLED to avoid Sarvam cost — it ran a speech-to-text pass on
        // every full article. The player falls back to its built-in
        // proportional timing estimate, so read-along still works (just less
        // word-precise). To re-enable, restore the alignAndStore call here.
        // if (SARVAM_KEY && target === "audio_url") {
        //   (globalThis as any).EdgeRuntime?.waitUntil?.(alignAndStore({
        //     wavBytes, articleId, languageCode: body.language || "te-IN",
        //     sarvamKey: SARVAM_KEY, supabase,
        //   }));
        // }
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
