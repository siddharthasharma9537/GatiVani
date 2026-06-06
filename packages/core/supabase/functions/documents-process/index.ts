import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { SarvamAIClient } from "npm:sarvamai@1.1.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-subscription-tier",
};

const TIER_MAX_PAGES: Record<string, number> = {
  free: 5,
  standard: 50,
  premium: 500,
  super_premium: 1000,
  super_premium_advanced: 9999,
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── 18-category detection ────────────────────────────────────────────────────

const CATEGORY_PATTERNS: Array<{ pattern: RegExp; label: string }> = [
  { pattern: /అంతర్జాతీయ|విదేశ|international|global|UN\b|usa|america|china|europe|world news/i, label: "International" },
  { pattern: /జాతీయ రాజకీయ|కాంగ్రెస్|బిజెపి|BJP|Congress|prime minister|మోదీ|జాతీయ నాయకుడు/i, label: "National Politics" },
  { pattern: /రాష్ట్ర రాజకీయ|TRS|BRS|YSRCP|TDP|JSP|Telangana|ముఖ్యమంత్రి|రేవంత్|చంద్రబాబు|జగన్/i, label: "State Politics" },
  { pattern: /సంపాదకీయ|editorial|opinion\b|views\b|వ్యాఖ్య|ఆలోచన/i, label: "Editorial" },
  { pattern: /పార్లమెంట్|parliamentary|lok sabha|rajya sabha|అసెంబ్లీ|legislation|చట్టసభ/i, label: "Parliamentary Affairs" },
  { pattern: /జాతీయ\b|national(?! politics)|central government|భారత ప్రభుత్వం/i, label: "National" },
  { pattern: /పథకం|scheme|yojana|welfare|సంక్షేమ|రాష్ట్ర పథకాలు|subsidy|భత్యం/i, label: "State Schemes" },
  { pattern: /ఆరోగ్య|health|medical|hospital|covid|వైద్య|వ్యాధి|వ్యాక్సిన్/i, label: "Health" },
  { pattern: /పర్యావరణ|environment|climate|green|forest|అడవి|వాతావరణ|pollution/i, label: "Environment" },
  { pattern: /న్యాయస్థాన|court|judiciary|judge|supreme court|high court|న్యాయ|verdict/i, label: "Judiciary" },
  { pattern: /విద్య|education|school|college|university|పాఠశాల|కళాశాల|exam|పరీక్ష/i, label: "Education" },
  { pattern: /మంత్రిత్వ|ministry|minister(?! prime)|department|విభాగ|secretary\b/i, label: "Ministry News" },
  { pattern: /ప్రముఖ|prominent|personality|celebrity|VIP|నాయకుడు|వ్యక్తి(?!.*విద్య)/i, label: "Prominent Persons" },
  { pattern: /ట్రెండింగ్|trending|viral|social media|twitter|instagram|facebook/i, label: "Trending News" },
  { pattern: /వైరల్ వీడియో|viral video|meme/i, label: "Viral News" },
  { pattern: /సినిమా|entertainment|film|movie|actor|actress|tollywood|బాలీవుడ్|serial/i, label: "Entertainment" },
  { pattern: /క్రికెట్|football|cricket|IPL|sports\b|game\b|ఆటలు|match\b|player\b|tournament/i, label: "Sports" },
  { pattern: /వ్యాపార|business|economy|market|stock|finance|banking|trade\b|shares/i, label: "Business" },
];

function deriveCategory(text: string): string {
  for (const { pattern, label } of CATEGORY_PATTERNS) {
    if (pattern.test(text)) return label;
  }
  return "News";
}

function cleanText(s: string): string {
  return s
    .replace(/\r\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]+/g, " ")
    .replace(/[ \t]+$/gm, "")
    .trim();
}

// ── Duration estimation (Telugu TTS ~700 chars/min) ──────────────────────────

function estimateDurationSeconds(text: string): number {
  return Math.max(15, Math.round((text.length / 700) * 60));
}

// ── Article segmentation ─────────────────────────────────────────────────────

interface ArticleSegment {
  title: string;
  content: string;
}

function segmentArticles(text: string, filename: string): ArticleSegment[] {
  const articles: ArticleSegment[] = [];

  // Strategy 1: markdown ## or # headers
  if (/^#{1,3}\s+.+/m.test(text)) {
    const lines = text.split("\n");
    let currentTitle = "";
    let currentLines: string[] = [];

    for (const line of lines) {
      const headerMatch = line.match(/^(#{1,3})\s+(.+)/);
      if (headerMatch) {
        const content = currentLines.join("\n").trim();
        if (currentTitle && content.length > 80) {
          articles.push({ title: currentTitle, content });
        }
        currentTitle = headerMatch[2].replace(/\*+/g, "").trim().slice(0, 120);
        currentLines = [];
      } else {
        currentLines.push(line);
      }
    }
    const lastContent = currentLines.join("\n").trim();
    if (currentTitle && lastContent.length > 80) {
      articles.push({ title: currentTitle, content: lastContent });
    }
  }

  // Strategy 2: blank-line paragraph segmentation
  if (articles.length < 2) {
    articles.length = 0;
    const paragraphs = text.split(/\n\n+/).map((p) => p.trim()).filter((p) => p.length > 100);
    for (const para of paragraphs) {
      const lines = para.split("\n").filter((l) => l.trim());
      if (!lines.length) continue;
      const firstLine = lines[0].replace(/^#+\s*/, "").trim();
      const rest = lines.slice(1).join("\n").trim();
      if (rest.length > 80) {
        articles.push({ title: firstLine.slice(0, 120), content: rest });
      } else {
        articles.push({ title: firstLine.slice(0, 120), content: para });
      }
    }
  }

  // Fallback: whole text as one article
  if (articles.length === 0) {
    const fallbackTitle = text.split("\n").find((l) => l.trim().length > 5)
      ?.replace(/^#+\s*/, "").trim() ?? filename.replace(/\.[^.]+$/, "");
    articles.push({ title: fallbackTitle.slice(0, 120), content: text });
  }

  return articles.slice(0, 15);
}

// ── OCR result extraction ─────────────────────────────────────────────────────

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

// ── Main handler ──────────────────────────────────────────────────────────────

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

    // ── Upload original to Supabase Storage ────────────────────────────────
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

    // ── Stage 1: Sarvam OCR ────────────────────────────────────────────────
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
        new Promise((_, reject) => setTimeout(() => reject(new Error("OCR timeout")), 55_000)),
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

    // ── Stage 2: Clean ─────────────────────────────────────────────────────
    const cleaned = cleanText(extractedText);

    // ── Stage 3: Segment into articles ─────────────────────────────────────
    const segments = segmentArticles(cleaned, originalName);

    const articles = segments.map((seg, i) => {
      const categoryInput = seg.title + " " + seg.content.slice(0, 300);
      const category = deriveCategory(categoryInput);
      const preview = seg.content.replace(/\n/g, " ").trim().slice(0, 200);
      const duration = estimateDurationSeconds(seg.content);
      return {
        id: `article_${ts}_${i + 1}`,
        title: seg.title,
        content: seg.content,
        preview,
        category,
        estimatedDurationSeconds: duration,
        audioUrl: null,
        page: 1,
      };
    });

    // ── Persist extracted text to DB ───────────────────────────────────────
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

    const processingTime = Math.round((Date.now() - startedAt) / 1000);

    return json({
      ok: true,
      newspaper: {
        id: `newspaper_${ts}`,
        title: originalName.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim(),
        date: new Date().toISOString().split("T")[0],
        storageUrl,
      },
      articles,
      summary: {
        totalArticles: articles.length,
        processingTime,
      },
      models: { ocr: "sarvam-ocr" },
      subscription: { tier, active: true },
      limits: { maxPages: cap, totalPages: 1, processedPages: 1, truncated: false },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-process]", err);
    return json({ error: "process_failed", message }, 500);
  }
});
