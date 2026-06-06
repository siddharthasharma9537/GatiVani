import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { SarvamAIClient } from "npm:sarvamai@1.1.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-subscription-tier",
};

const TIER_MAX_PAGES: Record<string, number> = { free: 5, standard: 50, premium: 500 };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const CATEGORY_PATTERNS: Array<{ pattern: RegExp; label: string }> = [
  { pattern: /రాజకీయ|పార్టీ|ఎన్నిక|ప్రభుత్వ|మంత్రి|cm|chief minister/i, label: "Politics" },
  { pattern: /క్రికెట్|ఫుట్‌బాల్|ఆటలు|క్రీడ|sports|cricket|ipl/i, label: "Sports" },
  { pattern: /వ్యాపార|మార్కెట్|సెన్సెక్స్|నిఫ్టీ|economy|stock|market/i, label: "Business" },
  { pattern: /సినిమా|చిత్రం|నటుడు|నటి|actor|film|tollywood/i, label: "Entertainment" },
  { pattern: /ఆరోగ్య|వైద్య|వ్యాధి|hospital|health|covid/i, label: "Health" },
  { pattern: /విద్య|పాఠశాల|కళాశాల|university|education|exam/i, label: "Education" },
];

function deriveCategory(text: string): string {
  for (const { pattern, label } of CATEGORY_PATTERNS) if (pattern.test(text)) return label;
  return "News";
}

function deriveTitle(text: string, fallback: string): string {
  const firstLine = text.split("\n").map((l) => l.trim()).find((l) => l.length > 0);
  if (!firstLine) return fallback;
  return firstLine.length > 80 ? firstLine.slice(0, 77) + "..." : firstLine;
}

function cleanText(s: string): string {
  return s
    .replace(/\r\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]+/g, " ")
    .replace(/[ \t]+$/gm, "")
    .trim();
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

async function extractTextFromSarvamDownloads(downloadUrls: Record<string, unknown>): Promise<string> {
  let best = "";
  for (const [filename, urlData] of Object.entries(downloadUrls)) {
    const url = typeof urlData === "object" && urlData && "file_url" in urlData
      ? (urlData as { file_url: string }).file_url
      : (urlData as string);
    if (typeof url !== "string" || !url.startsWith("http")) continue;

    try {
      const resp = await fetch(url);
      if (!resp.ok) continue;

      if (filename.endsWith(".zip")) {
        // Stream-extract the zip and pick the longest .md/.txt/.html entry
        const { ZipReader, BlobReader, TextWriter } = await import("https://deno.land/x/zipjs@v2.7.45/index.js");
        const zipReader = new ZipReader(new BlobReader(await resp.blob()));
        const entries = await zipReader.getEntries();
        for (const entry of entries) {
          if (entry.directory) continue;
          if (!/\.(md|html|txt)$/i.test(entry.filename)) continue;
          const content = await entry.getData?.(new TextWriter()) as string;
          if (content && content.length > best.length) best = content;
        }
        await zipReader.close();
      } else if (/\.(md|html|txt)$/i.test(filename) || filename === "data" || filename === "result") {
        const content = await resp.text();
        if (content && content.length > best.length) best = content;
      }
    } catch (e) {
      console.warn(`[OCR] Skipped ${filename}:`, (e as Error).message);
    }
  }
  return best;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const startedAt = Date.now();

  try {
    const SARVAM = Deno.env.get("SARVAM_API_KEY");
    if (!SARVAM) return json({ error: "config_missing", message: "SARVAM_API_KEY not configured" }, 500);

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!SUPABASE_URL || !SERVICE_KEY) {
      return json({ error: "config_missing", message: "Supabase env not configured" }, 500);
    }
    const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

    const tier = (req.headers.get("x-subscription-tier") || "free").toLowerCase();
    const cap = TIER_MAX_PAGES[tier] ?? TIER_MAX_PAGES.free;

    const form = await req.formData();
    const file = form.get("document");
    if (!(file instanceof File)) {
      return json({ error: "missing_file", message: 'Expected multipart field "document".' }, 400);
    }
    if (file.size > 25 * 1024 * 1024) {
      return json({ error: "file_too_large", message: "Maximum size is 25 MB." }, 413);
    }

    const ts = Date.now();
    const originalName = file.name || "upload";
    const safeName = `${ts}_${originalName.replace(/[^a-zA-Z0-9._-]/g, "_")}`;
    const buffer = new Uint8Array(await file.arrayBuffer());

    // Persist original to Supabase Storage (uploads bucket)
    let storageUrl = "";
    {
      const { error } = await supabase.storage
        .from("uploads")
        .upload(safeName, buffer, { contentType: file.type || "application/octet-stream", upsert: false });
      if (error) {
        console.warn("[upload] Storage error:", error.message);
      } else {
        const { data } = supabase.storage.from("uploads").getPublicUrl(safeName);
        storageUrl = data.publicUrl;
      }
    }

    // ── Stage 1: Sarvam OCR ─────────────────────────────────────────
    let extractedText = "";
    const tempPath = `/tmp/sarvam_${ts}_${safeName}`;
    try {
      await Deno.writeFile(tempPath, buffer);
      const sarvam = new SarvamAIClient({ apiSubscriptionKey: SARVAM });

      console.log("[stage1] Creating Sarvam document intelligence job...");
      const job = await sarvam.documentIntelligence.createJob({
        language: "te-IN",
        outputFormat: "md",
      });
      console.log(`[stage1] Job: ${(job as { jobId?: string }).jobId}`);

      await (job as { uploadFile: (p: string) => Promise<unknown> }).uploadFile(tempPath);
      await (job as { start: () => Promise<unknown> }).start();
      await Promise.race([
        (job as { waitUntilComplete: () => Promise<unknown> }).waitUntilComplete(),
        new Promise((_, reject) => setTimeout(() => reject(new Error("OCR timeout")), 45_000)),
      ]);

      const links = await (job as { getDownloadLinks: () => Promise<{ download_urls?: Record<string, unknown> }> }).getDownloadLinks();
      if (links?.download_urls) {
        extractedText = await extractTextFromSarvamDownloads(links.download_urls);
      }
    } catch (e) {
      console.error("[stage1] OCR failed:", (e as Error).message);
    } finally {
      try { await Deno.remove(tempPath); } catch { /* ignore */ }
    }

    if (!extractedText || extractedText.length < 10) {
      extractedText = `Document: ${originalName}`;
    }

    // ── Stage 2: Cleaning ──────────────────────────────────────────
    const cleaned = cleanText(extractedText);

    // ── Stage 3: TTS via Sarvam ────────────────────────────────────
    let audioUrl = "";
    const textForTTS = cleaned.slice(0, 2000).trim();
    if (textForTTS.length > 0) {
      try {
        // Call Sarvam TTS REST API directly (skips SDK to avoid Node-compat edge cases)
        const sarvamResp = await fetch("https://api.sarvam.ai/text-to-speech", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "api-subscription-key": SARVAM,
          },
          body: JSON.stringify({
            text: textForTTS,
            target_language_code: "te-IN",
            speaker: "shubh",
            pace: 1.1,
            speech_sample_rate: 48000,
            enable_preprocessing: true,
            model: "bulbul:v3",
          }),
        });

        if (!sarvamResp.ok) {
          console.warn(`[tts] sarvam ${sarvamResp.status}: ${(await sarvamResp.text()).slice(0, 200)}`);
        } else {
          const ttsJson = await sarvamResp.json() as { audios?: string[] };
          const audioB64 = ttsJson?.audios?.[0];
          if (audioB64) {
            const audioBytes = base64ToBytes(audioB64);
            const audioName = `${ts}_audio.mp3`;
            const { error: audioErr } = await supabase.storage
              .from("audio")
              .upload(audioName, audioBytes, { contentType: "audio/mpeg" });
            if (audioErr) {
              console.warn("[tts] storage error:", audioErr.message);
            } else {
              audioUrl = supabase.storage.from("audio").getPublicUrl(audioName).data.publicUrl;
            }
          }
        }
      } catch (e) {
        console.error("[tts] exception:", (e as Error).message);
      }
    }

    // ── Persist extracted text to DB ───────────────────────────────
    await supabase.from("extracted_texts").insert({
      filename: originalName,
      mime_type: file.type || null,
      file_size: file.size,
      text: cleaned,
      language: "te",
      source: "ocr",
      confidence: 0.8,
    }).then(({ error }) => {
      if (error) console.warn("[db] insert error:", error.message);
    });

    // ── Build response (matches Flutter DocumentService shape) ─────
    const title = deriveTitle(cleaned, originalName);
    const section = deriveCategory(cleaned);
    const preview = cleaned.slice(0, 200);
    const processingTime = Math.round((Date.now() - startedAt) / 1000);

    return json({
      ok: true,
      newspaper: {
        id: `newspaper_${ts}`,
        title: originalName,
        date: new Date().toISOString().split("T")[0],
        storageUrl,
      },
      articles: [{
        id: "article_1",
        title,
        section,
        preview,
        audioUrl,
        qualityScore: audioUrl ? 85 : 40,
        status: audioUrl ? "completed" : "failed",
        page: 1,
      }],
      summary: {
        totalArticles: 1,
        processedArticles: audioUrl ? 1 : 0,
        failedArticles: audioUrl ? 0 : 1,
        processingTime,
      },
      models: { ocr: "sarvam-ocr", tts: "sarvam-tts" },
      subscription: { tier, active: true },
      limits: { maxPages: cap, totalPages: 1, processedPages: 1, truncated: false },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-process]", err);
    return json({ error: "process_failed", message }, 500);
  }
});
