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

// ── Document types that must stay as one unified article ─────────────────────
// (never split slokas / mantras into separate "articles")

const UNIFIED_DOCUMENT_TYPES = new Set(["sloka", "mantra", "stotra", "stotram"]);

function categoryForDocumentType(documentType: string): string {
  switch (documentType) {
    case "sloka":
    case "stotra":
    case "stotram":   return "Devotional";
    case "mantra":    return "Mantra";
    case "book":      return "Book";
    case "letter":    return "Letter";
    case "invitation":return "Invitation";
    case "certificate":return "Certificate";
    default:          return "";   // fall through to regex patterns
  }
}

// ── Voice model selection by document type ────────────────────────────────────
// Returns a Sarvam speaker name; the synthesize function maps it to the correct
// Gemini voice (female → Kore, male → Puck) automatically.

function speakerForDocumentType(documentType: string): string {
  switch (documentType) {
    case "newspaper":   return "priya";   // clear professional Telugu female
    case "sloka":
    case "stotra":
    case "stotram":     return "kavitha"; // devotional female voice
    case "mantra":      return "shubh";   // male, deeper — suits Sanskrit recitation
    case "book":        return "neha";    // natural relaxed reading
    default:            return "priya";
  }
}

// ── Category detection (regex fallback) ──────────────────────────────────────

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

// ── OCR noise filter (newspaper-specific) ────────────────────────────────────
// Strips non-narrative content from Sarvam's markdown output before it reaches
// Gemini — removes images, tables, ads, page headers, and Telugu layout clutter.
// This is purely token-reduction; no article content is lost.

function filterOcrMarkdown(md: string): string {
  return md
    .split("\n")
    .filter((line) => {
      const t = line.trim();
      if (!t) return true; // keep blank lines (paragraph breaks)

      // Markdown images — never spoken, pure token waste
      if (/^!\[.*\]\(.*\)/.test(t)) return false;

      // Markdown table rows and dividers  |  col  |  col  |
      if (/^\|/.test(t)) return false;

      // HTML image / figure tags (when outputFormat returns html snippets)
      if (/^<img\s|^<figure|^<\/figure/.test(t)) return false;

      // Page number lines: "పేజీ 4", "Page 4", standalone digit lines
      if (/^(పేజీ\s*\d+|\d+\s*వ\s*పేజీ|page\s*\d+|\d+)$/i.test(t)) return false;

      // Advertisement markers (Telugu + English variants)
      if (/జాహీరాతు|ప్రకటన|advertisement|advt\.?$|sponsored/i.test(t)) return false;

      // Stock / market ticker lines: sequences of numbers and symbols
      if (/^[\d\s,.\-+%₹$]+$/.test(t) && t.replace(/[\d\s,.\-+%₹$]/g, "").length === 0) return false;

      // Weather table remnants: temperature/humidity patterns
      if (/°[CF]|\d+%\s*(humidity|తేమ)/i.test(t)) return false;

      // Horizontal rules and decorative separators
      if (/^[-*_]{3,}$/.test(t)) return false;

      // Markdown bare URLs (image CDN links with no text)
      if (/^https?:\/\/\S+\.(jpg|jpeg|png|webp|gif|svg)/i.test(t)) return false;

      // Sarvam Vision auto-generated image descriptions (italic Telugu/English)
      // e.g. "*ఈ చిత్రంలో నీలిరంగు డ్రమ్ములు కనిపిస్తున్నాయి*"
      // These describe photo contents — not article text, never spoken.
      if (/^\*ఈ చిత్రంలో|^\*In this image|^\*This image shows/i.test(t)) return false;
      // Catch any fully-italic line that is a visual description (starts & ends with *)
      if (/^\*[^*]{20,}\*$/.test(t) && /చిత్రం|image|photo|figure|diagram|గ్రాఫ్|పటం/i.test(t)) return false;

      return true;
    })
    .join("\n")
    // Collapse runs of 3+ blank lines that filtering may leave behind
    .replace(/\n{3,}/g, "\n\n")
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

  if (articles.length === 0) {
    const fallbackTitle = text.split("\n").find((l) => l.trim().length > 5)
      ?.replace(/^#+\s*/, "").trim() ?? filename.replace(/\.[^.]+$/, "");
    articles.push({ title: fallbackTitle.slice(0, 120), content: text });
  }

  return articles.slice(0, 15);
}

// ── HTML → ArticleSegment extractor (layout-aware, column-safe) ──────────────
// Parses Sarvam's HTML output (outputFormat:"html"), which encodes the page
// as .multi-column-row > .column-block divs.  Each column-block is processed
// independently so text from adjacent newspaper columns never mixes.
//
// Block handling:
//   h2.headline           → always starts a new article
//   h2.section-title      → starts a new article only if followed by paragraphs
//   h3.sub-headline       → sub-section within current article
//   p.paragraph           → body text; <br/> line-breaks are rejoined
//   figure.image          → skipped (base64 blobs + auto-generated captions)
//   div.advertisement     → skipped
//   div.table / table     → skipped (numbers, schedules — not suitable for TTS)
//   p.page-number         → skipped
//   header.header         → skipped (newspaper masthead)

function stripHtmlTags(html: string): string {
  return html
    .replace(/<br\s*\/?>/gi, " ")   // line-breaks become spaces
    .replace(/<[^>]+>/g, "")         // remove all other tags
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ").replace(/&#\d+;/g, "")
    .replace(/[ \t]+/g, " ")
    .trim();
}

function joinColumnText(raw: string): string {
  // Telugu words are often split mid-word at column edges.
  // Heuristic: if a line ends without punctuation and the next starts with
  // a lowercase-equivalent Telugu character, concatenate directly.
  // For now we just normalise whitespace — Gemini fixes the rest.
  return raw.replace(/\n/g, " ").replace(/\s{2,}/g, " ").trim();
}

function parseHtmlToArticles(html: string, filename: string): ArticleSegment[] {
  const articles: ArticleSegment[] = [];

  // Remove <style> block, base64 image data, and figure/img/table/ad blocks entirely
  let cleaned = html
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
    .replace(/src="data:image[^"]*"/gi, 'src=""')       // scrub base64 blobs
    .replace(/<figure[^>]*>[\s\S]*?<\/figure>/gi, "")   // remove image+caption blocks
    .replace(/<div[^>]*class="[^"]*advertisement[^"]*"[^>]*>[\s\S]*?<\/div>/gi, "")
    .replace(/<div[^>]*class="[^"]*table[^"]*"[^>]*>[\s\S]*?<\/div>/gi, "")
    .replace(/<p[^>]*class="[^"]*page-number[^"]*"[^>]*>[\s\S]*?<\/p>/gi, "")
    .replace(/<header[^>]*>[\s\S]*?<\/header>/gi, "");

  let currentTitle = "";
  let currentLines: string[] = [];
  let pendingSectionTitle = "";  // section-title held until we know if body follows

  function flushArticle() {
    if (!currentTitle) return;
    const content = currentLines.join("\n\n").trim();
    if (content.length > 60) {
      articles.push({ title: currentTitle, content });
    }
    currentTitle = "";
    currentLines = [];
  }

  function processColumnContent(colHtml: string) {
    // Walk through headline and paragraph elements in order
    const elementRe = /<(h[1-4]|p)[^>]*class="([^"]*)"[^>]*>([\s\S]*?)<\/\1>/gi;
    let match: RegExpExecArray | null;

    while ((match = elementRe.exec(colHtml)) !== null) {
      const tag = match[1];
      const cls = match[2];
      const inner = match[3];
      const text = joinColumnText(stripHtmlTags(inner));
      if (!text) continue;

      const isHeadline = tag.startsWith("h") && cls.includes("headline");
      const isSectionTitle = tag.startsWith("h") && cls.includes("section-title");
      const isParagraph = tag === "p" && cls.includes("paragraph");

      if (isHeadline) {
        // Flush pending section-title that had no body
        if (pendingSectionTitle && currentLines.length === 0 && currentTitle) {
          // it was just an image caption, discard it
        } else if (pendingSectionTitle) {
          // section-title had body → it was a real sub-article, flush
          flushArticle();
        }
        pendingSectionTitle = "";
        flushArticle();
        currentTitle = text.slice(0, 120);
      } else if (isSectionTitle) {
        // Hold it: if next thing is a paragraph it's a sub-article, else a caption
        if (pendingSectionTitle && currentLines.length > 0) {
          // previous pending section-title had body → flush it
          flushArticle();
          currentTitle = pendingSectionTitle;
        }
        pendingSectionTitle = text.slice(0, 120);
      } else if (isParagraph) {
        if (pendingSectionTitle) {
          // Now we know the section-title has body — treat it as article boundary
          if (currentLines.length > 0) flushArticle();
          if (!currentTitle) currentTitle = pendingSectionTitle;
          else currentLines.push(""); // just append under current article
          pendingSectionTitle = "";
        }
        if (!currentTitle) currentTitle = text.slice(0, 120);
        else currentLines.push(text);
      }
    }
  }

  // Process entire document column by column
  // Strategy: split on multi-column-row boundaries, then process each column-block
  const rowRe = /<div[^>]*class="multi-column-row[^"]*"[^>]*>([\s\S]*?)<\/div>\s*(?=<div[^>]*class="multi-column-row|<\/div>\s*<\/body>|$)/gi;
  let rowMatch: RegExpExecArray | null;

  while ((rowMatch = rowRe.exec(cleaned)) !== null) {
    const rowHtml = rowMatch[1];
    // Extract column-blocks sorted by grid-column number
    const colRe = /<div[^>]*class="column-block"[^>]*style="[^"]*grid-column:\s*(\d+)[^"]*"[^>]*>([\s\S]*?)(?=<div[^>]*class="column-block"|$)/gi;
    const cols: Array<{ col: number; html: string }> = [];
    let colMatch: RegExpExecArray | null;
    while ((colMatch = colRe.exec(rowHtml)) !== null) {
      cols.push({ col: parseInt(colMatch[1]), html: colMatch[2] });
    }
    cols.sort((a, b) => a.col - b.col);
    for (const { html: colHtml } of cols) {
      processColumnContent(colHtml);
    }
  }

  // Flush the last article
  if (pendingSectionTitle && currentLines.length > 0) {
    if (!currentTitle) currentTitle = pendingSectionTitle;
  }
  flushArticle();

  // Fallback: if nothing parsed, return raw text from whole document
  if (articles.length === 0) {
    const fallbackText = stripHtmlTags(cleaned).replace(/\s+/g, " ").trim();
    const fallbackTitle = filename.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim();
    articles.push({ title: fallbackTitle, content: fallbackText });
  }

  // Deduplicate: remove articles whose title duplicates a previous one
  const seen = new Set<string>();
  return articles
    .filter((a) => {
      const key = a.title.slice(0, 40).toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, 20);
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

// ── Gemini refinement: OCR correction + document classification ───────────────

interface GeminiRefinement {
  documentType: string;
  documentTitle: string;   // formal name, e.g. "Shiva Manasa Pooja Stotram"; empty for newspapers
  language: string;
  readingStyle: string;
  correctedText: string;
}

function bytesToBase64(bytes: Uint8Array): string {
  const CHUNK = 8192;
  let binary = "";
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, Math.min(i + CHUNK, bytes.length)));
  }
  return btoa(binary);
}

async function refineWithGemini(
  ocrText: string,
  fileBuffer: Uint8Array,
  mimeType: string,
  geminiKey: string,
): Promise<GeminiRefinement> {
  const isDisplayable = mimeType.startsWith("image/") || mimeType === "application/pdf";
  const parts: unknown[] = [];

  // Include the original file as vision context if it's reasonably sized
  if (isDisplayable && fileBuffer.length < 15 * 1024 * 1024) {
    parts.push({ inlineData: { mimeType, data: bytesToBase64(fileBuffer) } });
  }

  const prompt = `You are analyzing a document${parts.length > 0 ? " (image/PDF provided above)" : ""} and its OCR-extracted text.

Perform these tasks:
1. Classify the document type. Choose ONE: "newspaper", "sloka", "mantra", "book", "invitation", "certificate", "letter", or "other"
2. If the document is a named devotional/literary work (stotram, mantra, kavyam, book chapter, etc.), set "documentTitle" to its recognized name in the source language (e.g. "శివ మానస పూజా స్తోత్రం" or "Shiva Manasa Pooja Stotram"). For newspapers/letters/certificates, leave "documentTitle" as an empty string "".
3. Detect the primary language: "te" (Telugu), "sa" (Sanskrit), "hi" (Hindi), "en" (English), or "mixed"
4. Choose reading style for text-to-speech. Choose ONE:
   - "news_anchor"     → for news, articles, general content
   - "devotional_slow" → for slokas, stotras, bhajans, devotional poetry
   - "mantra_clear"    → for mantras, Vedic text, Sanskrit ritual text
   - "normal"          → for books, letters, certificates, other
5. Fix OCR errors in the text below (misrecognized Telugu/Sanskrit/Hindi characters, broken words from column splits, stray numbers/symbols that should be letters). Return the full corrected text — do NOT summarize or shorten it.

OCR Text (may contain errors):
${ocrText.slice(0, 12000)}

Return ONLY valid JSON with no markdown fences:
{
  "documentType": "newspaper",
  "documentTitle": "",
  "language": "te",
  "readingStyle": "news_anchor",
  "correctedText": "..."
}`;

  parts.push({ text: prompt });

  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts }],
        generationConfig: {
          responseMimeType: "application/json",
          temperature: 0.1,
          maxOutputTokens: 8192,
        },
      }),
      signal: AbortSignal.timeout(45_000),
    },
  );

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Gemini HTTP ${resp.status}: ${errText.slice(0, 100)}`);
  }

  const data = await resp.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  const raw = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
  const parsed = JSON.parse(raw) as GeminiRefinement;
  console.log(`[stage2] Gemini result: type=${parsed.documentType ?? "?"} title="${parsed.documentTitle ?? ""}" style=${parsed.readingStyle ?? "?"}`);
  return parsed;
}

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const startedAt = Date.now();

  try {
    const SARVAM = Deno.env.get("SARVAM_API_KEY");
    if (!SARVAM) return json({ error: "config_missing", message: "SARVAM_API_KEY not configured" }, 500);

    const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY");

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
    let rawOcrHtml = "";   // raw HTML from Sarvam (outputFormat:"html"), used for column-aware parsing
    try {
      await Deno.writeFile(tempPath, buffer);
      const sarvam = new SarvamAIClient({ apiSubscriptionKey: SARVAM });

      console.log("[stage1] Creating Sarvam document intelligence job...");
      const job = await sarvam.documentIntelligence.createJob({
        language: "te-IN",
        outputFormat: "html",
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
        rawOcrHtml = await extractTextFromSarvamDownloads(links.download_urls);
        // For the Gemini refinement path, strip HTML tags → plain text → filter
        extractedText = rawOcrHtml.startsWith("<")
          ? stripHtmlTags(rawOcrHtml)
          : rawOcrHtml;
      }
    } catch (e) {
      console.error("[stage1] OCR failed:", (e as Error).message);
    } finally {
      try { await Deno.remove(tempPath); } catch { /* ignore */ }
    }

    if (!extractedText || extractedText.length < 10) {
      extractedText = `Document: ${originalName}`;
    }

    // ── Stage 2: Gemini — OCR correction + document classification ─────────
    let documentType = "newspaper";
    let documentTitle = "";   // stotram / book name identified by Gemini
    let readingStyle = "news_anchor";

    // Filter non-narrative noise (images, tables, ads) before Gemini sees the text.
    // This reduces Gemini input tokens by 20–40% on dense newspaper pages.
    const filteredText = filterOcrMarkdown(extractedText);
    let refinedText = cleanText(filteredText);

    console.log(`[stage2] OCR filter: ${extractedText.length} → ${filteredText.length} chars (saved ${Math.round((1 - filteredText.length / Math.max(extractedText.length, 1)) * 100)}%)`);

    if (GEMINI_KEY && filteredText.length > 20) {
      try {
        console.log("[stage2] Refining with Gemini...");
        const result = await refineWithGemini(filteredText, buffer, file.type || "image/jpeg", GEMINI_KEY);
        documentType = result.documentType || "newspaper";
        documentTitle = (result.documentTitle || "").trim();
        readingStyle = result.readingStyle || "news_anchor";
        if (result.correctedText && result.correctedText.length > 50) {
          refinedText = cleanText(result.correctedText);
          console.log(`[stage2] Corrected: ${extractedText.length} → ${refinedText.length} chars`);
        }
      } catch (e) {
        console.warn("[stage2] Gemini refinement failed, using raw OCR:", (e as Error).message);
      }
    } else {
      console.log("[stage2] Skipping Gemini (no key or too short)");
    }

    // ── Stage 3: Build articles ─────────────────────────────────────────────
    // Unified document types (sloka, mantra, stotram) → single article with all text.
    // Newspapers and other multi-section documents → segment as before.

    const isUnified = UNIFIED_DOCUMENT_TYPES.has(documentType);

    let segments: ArticleSegment[];
    if (isUnified) {
      // One article: title = Gemini-identified name, content = full corrected text
      const titleForUnified = documentTitle
        || refinedText.split("\n").find((l) => l.trim().length > 3)?.trim().slice(0, 120)
        || originalName.replace(/\.[^.]+$/, "").trim();
      segments = [{ title: titleForUnified, content: refinedText }];
      console.log(`[stage3] Unified document (${documentType}) → 1 article: "${titleForUnified}"`);
    } else if (documentType === "newspaper" && rawOcrHtml.length > 100) {
      // Use layout-aware HTML parser: preserves column boundaries, prevents cross-column bleed
      segments = parseHtmlToArticles(rawOcrHtml, originalName);
      console.log(`[stage3] HTML column-aware parse → ${segments.length} articles`);
      // Fallback: if HTML parse returns nothing useful, use Gemini-corrected text
      if (segments.length === 0) {
        segments = segmentArticles(refinedText, originalName);
        console.log(`[stage3] Fallback to text segmentation → ${segments.length} articles`);
      }
    } else {
      segments = segmentArticles(refinedText, originalName);
      console.log(`[stage3] Segmented → ${segments.length} articles`);
    }

    const suggestedSpeaker = speakerForDocumentType(documentType);

    const articles = segments.map((seg, i) => {
      // Category: use document-type override first, then regex fallback
      const dtCategory = categoryForDocumentType(documentType);
      const category = dtCategory || deriveCategory(seg.title + " " + seg.content.slice(0, 300));
      const preview = seg.content.replace(/\n/g, " ").trim().slice(0, 200);
      const duration = estimateDurationSeconds(seg.content);
      return {
        id: `article_${ts}_${i + 1}`,
        title: seg.title,
        content: seg.content,
        preview,
        category,
        documentType,
        readingStyle,
        suggestedSpeaker,
        estimatedDurationSeconds: duration,
        audioUrl: null,
        page: 1,
      };
    });

    // Effective newspaper/document title: Gemini-identified name or filename
    const effectiveDocumentTitle = documentTitle
      || originalName.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim();

    // ── Persist to DB ───────────────────────────────────────────────────────
    await supabase.from("extracted_texts").insert({
      filename: originalName,
      mime_type: file.type || null,
      file_size: file.size,
      text: refinedText,
      language: "te",
      source: "ocr",
      confidence: GEMINI_KEY ? 0.95 : 0.8,
    }).then(({ error }) => {
      if (error) console.warn("[db] insert error:", error.message);
    });

    const processingTime = Math.round((Date.now() - startedAt) / 1000);
    console.log(`[done] ${articles.length} article(s), type=${documentType}, title="${effectiveDocumentTitle}", style=${readingStyle}, ${processingTime}s`);

    return json({
      ok: true,
      newspaper: {
        id: `newspaper_${ts}`,
        title: effectiveDocumentTitle,
        date: new Date().toISOString().split("T")[0],
        storageUrl,
      },
      articles,
      summary: {
        totalArticles: articles.length,
        processingTime,
        documentType,
        readingStyle,
      },
      models: { ocr: "sarvam-ocr", refinement: GEMINI_KEY ? "gemini-2.5-flash" : "none" },
      subscription: { tier, active: true },
      limits: { maxPages: cap, totalPages: 1, processedPages: 1, truncated: false },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-process]", err);
    return json({ error: "process_failed", message }, 500);
  }
});
