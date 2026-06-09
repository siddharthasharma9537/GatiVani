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
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ").replace(/&#\d+;/g, "")
    .replace(/[ \t]+/g, " ")
    .trim();
}

function joinColumnText(raw: string): string {
  return raw.replace(/\n/g, " ").replace(/\s{2,}/g, " ").trim();
}

// ── Depth-tracking div extractor ─────────────────────────────────────────────
// Problem with lazy regex ([\s\S]*?<\/div>): it stops at the FIRST </div>
// inside the container, which is the end of the first nested child, not the
// container itself.  A depth counter correctly pairs every open with its close.

function extractDivContent(html: string, afterOpenTag: number): { content: string; end: number } {
  let depth = 1;
  let i = afterOpenTag;
  while (i < html.length) {
    const o = html.indexOf("<div", i);
    const c = html.indexOf("</div>", i);
    if (c === -1) break;
    if (o !== -1 && o < c) {
      const ch = html[o + 4];
      if (ch === " " || ch === ">" || ch === "\n" || ch === "\r" || ch === "\t") depth++;
      i = o + 5;
    } else {
      depth--;
      if (depth === 0) return { content: html.slice(afterOpenTag, c), end: c + 6 };
      i = c + 6;
    }
  }
  return { content: html.slice(afterOpenTag), end: html.length };
}

function findDivsByClass(html: string, classSubstr: string): Array<{ attrs: string; content: string; end: number }> {
  const results: Array<{ attrs: string; content: string; end: number }> = [];
  let i = 0;
  while (i < html.length) {
    const tagStart = html.indexOf("<div", i);
    if (tagStart === -1) break;
    const tagEnd = html.indexOf(">", tagStart);
    if (tagEnd === -1) break;
    const openTag = html.slice(tagStart, tagEnd + 1);
    if (openTag.includes(classSubstr)) {
      const { content, end } = extractDivContent(html, tagEnd + 1);
      results.push({ attrs: openTag, content, end });
      i = end; // skip past whole div — don't match nested same-class divs
    } else {
      i = tagEnd + 1;
    }
  }
  return results;
}

function parseHtmlToArticles(html: string, filename: string): ArticleSegment[] {
  const articles: ArticleSegment[] = [];

  // Strip whole-document noise that doesn't contain nested <div>s
  const doc = html
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
    .replace(/src="data:image[^"]*"/gi, 'src=""')
    .replace(/<header[^>]*>[\s\S]*?<\/header>/gi, "");

  // Byline pattern for detecting embedded datelines mid-paragraph:
  //   "Location, న్యూస్టుడే: body..."   (location first)
  //   "న్యూస్టుడే, Location: body..."   (tag first)
  const INLINE_BYLINE_RE = /(?:[^,\n]{2,50},\s*న్యూస్\s*టుడే|న్యూస్\s*టుడే\s*,\s*[^:\n]{2,60})\s*[:]\s*/;

  let currentTitle = "";
  let currentLines: string[] = [];
  let pendingSectionTitle = "";

  /**
   * mergeParagraphs(paras)
   * Heuristically merges paragraphs that are continuations.
   * Strategy:
   *   1. First, pair consecutive bullets with following body paragraphs
   *   2. Then, merge remaining paragraphs that end abruptly (cut off mid-sentence)
   */
  function mergeParagraphs(paras: string[]): string[] {
    if (paras.length === 0) return paras;

    // Step 1: Pair consecutive bullets with following body paragraphs
    // Pattern: BULLETs followed by BODYs → pair them in order
    // E.g., BULLET BULLET BODY BODY → (BULLET+BODY) (BULLET+BODY)
    const pairedParas: string[] = [];
    let i = 0;
    while (i < paras.length) {
      const current = paras[i];
      const isBullet = current.startsWith("•");

      if (isBullet) {
        // Look ahead to count consecutive bullets
        let bulletEnd = i;
        while (bulletEnd + 1 < paras.length && paras[bulletEnd + 1].startsWith("•")) {
          bulletEnd++;
        }
        const bulletCount = bulletEnd - i + 1;

        // Count how many bodies follow immediately after
        let bodyEnd = bulletEnd;
        while (bodyEnd + 1 < paras.length && !paras[bodyEnd + 1].startsWith("•")) {
          bodyEnd++;
        }
        const bodyCount = bodyEnd - bulletEnd;

        // Pair up bullets with bodies in order
        for (let j = 0; j < bulletCount && i + j < paras.length; j++) {
          let pairedText = paras[i + j];
          if (j < bodyCount && bulletEnd + 1 + j < paras.length) {
            const bodyIdx = bulletEnd + 1 + j;
            pairedText = pairedText + " " + paras[bodyIdx];
          }
          pairedParas.push(pairedText);
        }

        // Skip the bullets and paired bodies
        i = bulletEnd + 1 + Math.min(bulletCount, bodyCount);
      } else {
        pairedParas.push(current);
        i++;
      }
    }

    // Step 2: Merge paragraphs that end abruptly
    const result: string[] = [];
    for (let i = 0; i < pairedParas.length; i++) {
      let current = pairedParas[i];
      const trimmed = current.trim();
      const endsCleanly = /(।।?|[.!?:])\s*$/.test(trimmed) || trimmed === "";
      const endsAbruptly = !endsCleanly && trimmed.length > 0;

      // If current ends abruptly, merge with next (but only if next is body text and not a bullet)
      if (endsAbruptly && i + 1 < pairedParas.length) {
        const next = pairedParas[i + 1].trim();
        if (next.length > 0 && !next.startsWith("•")) {
          current = current + " " + next;
          i++; // skip next, we merged it
        }
      }
      result.push(current.trim());
    }

    return result.filter(p => p.trim().length > 0);
  }

  function flushArticle() {
    if (!currentTitle) return;
    // Merge paragraphs before joining
    const merged = mergeParagraphs(currentLines);
    const content = merged.join("\n\n").trim();
    if (content.length > 60) articles.push({ title: currentTitle, content });
    currentTitle = "";
    currentLines = [];
  }

  function processColumn(colContent: string) {
    // Strip noise blocks safe for lazy regex (no nested <div> inside them)
    const clean = colContent
      .replace(/<figure[^>]*>[\s\S]*?<\/figure>/gi, "")
      .replace(/<p[^>]*class="[^"]*page-number[^"]*"[^>]*>[\s\S]*?<\/p>/gi, "")
      .replace(/<div[^>]*class="[^"]*advertisement[^"]*"[^>]*>[\s\S]*?<\/div>/gi, "")
      .replace(/<div[^>]*class="[^"]*table[^"]*"[^>]*>[\s\S]*?<\/div>/gi, "");

    const elementRe = /<(h[1-4]|p)([^>]*)>([\s\S]*?)<\/\1>/gi;
    let m: RegExpExecArray | null;
    while ((m = elementRe.exec(clean)) !== null) {
      const tag = m[1];
      const attrs = m[2];
      const inner = m[3];
      const cls = (attrs.match(/class="([^"]*)"/) ?? [])[1] ?? "";
      let text = joinColumnText(stripHtmlTags(inner));
      if (!text) continue;

      const isHeadline     = tag.startsWith("h") && cls.includes("headline");
      const isSectionTitle = tag.startsWith("h") && cls.includes("section-title");
      const isParagraph    = tag === "p" && cls.includes("paragraph");

      if (isHeadline) {
        if (pendingSectionTitle) flushArticle();
        pendingSectionTitle = "";
        flushArticle();
        currentTitle = text.slice(0, 120);
      } else if (isSectionTitle) {
        // If we're already inside an article body (title + content), this is a photo/image
        // caption embedded mid-article — skip it so it doesn't flush the article prematurely.
        if (currentTitle && currentLines.length > 0) {
          // caption inside a running article — ignore
        } else {
          if (pendingSectionTitle && currentLines.length > 0) {
            flushArticle();
            currentTitle = pendingSectionTitle;
          }
          pendingSectionTitle = text.slice(0, 120);
        }
      } else if (isParagraph) {
        if (pendingSectionTitle) {
          if (currentLines.length > 0) flushArticle();
          if (!currentTitle) currentTitle = pendingSectionTitle;
          pendingSectionTitle = "";
        }
        // Fix A: if the FIRST paragraph under a headline contains a byline mid-text,
        // strip everything before the byline — that prefix is the orphaned tail of the
        // previous column's article that Sarvam bled into this block.
        // e.g. "న్యాయం జరుగుతుందని... న్యూస్టుడే, కరీంనగర్ రవాణా విభాగం: [real body]"
        if (currentLines.length === 0 && currentTitle) {
          const bylineIdx = text.search(INLINE_BYLINE_RE);
          if (bylineIdx > 5) {
            text = text.slice(bylineIdx).replace(INLINE_BYLINE_RE, "").trim();
          }
        }
        // Fix B: if the SECOND paragraph STARTS with a byline (index 0–4), the first
        // paragraph was a pure orphan with no byline of its own — discard it.
        // e.g. currentLines[0] = "న్యాయం జరుగు తుందని సర్కారు భావించింది." ← orphan
        //      text             = "న్యూస్టుడే, కరీంనగర్ రవాణా విభాగం: రాష్ట్ర..."
        if (currentLines.length === 1 && currentTitle) {
          const bylineIdx = text.search(INLINE_BYLINE_RE);
          if (bylineIdx >= 0 && bylineIdx < 5) {
            currentLines = [];
            text = text.slice(bylineIdx).replace(INLINE_BYLINE_RE, "").trim();
          }
        }
        if (!currentTitle) currentTitle = text.slice(0, 120);
        else if (text) currentLines.push(text);
      }
    }
  }

  // Walk rows → columns in grid-column order using depth-tracking extractors
  const rows = findDivsByClass(doc, "multi-column-row");
  for (const row of rows) {
    const cols = findDivsByClass(row.content, "column-block");
    cols.sort((a, b) => {
      const na = parseInt((a.attrs.match(/grid-column:\s*(\d+)/) ?? [])[1] ?? "0");
      const nb = parseInt((b.attrs.match(/grid-column:\s*(\d+)/) ?? [])[1] ?? "0");
      return na - nb;
    });
    for (const col of cols) processColumn(col.content);
  }

  if (pendingSectionTitle && !currentTitle) currentTitle = pendingSectionTitle;
  flushArticle();

  if (articles.length === 0) {
    const fallbackText = stripHtmlTags(doc).replace(/\s+/g, " ").trim();
    const fallbackTitle = filename.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim();
    articles.push({ title: fallbackTitle, content: fallbackText });
  }

  const seen = new Set<string>();
  return articles
    .filter((a) => {
      const key = a.title.slice(0, 40).toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, 30);
}

// ── Gemini content correction for HTML-parsed articles ───────────────────────
// parseHtmlToArticles() uses the raw Sarvam HTML which contains OCR errors
// (e.g. "రైతు ఓదెల ళిక చేసుకున్నా" instead of "రైతు ఓదెల రాజు").
// Gemini's correctedText has those errors fixed, but it's a flat string with no
// column structure.  We get the best of both worlds by:
//   1. Using HTML parsing for article boundary detection (titles, order)
//   2. Replacing each article's body with the matching section from Gemini text
//
// The match is anchored on the article title's first 20 chars — headlines OCR
// cleanly because they are set in larger/bolder type on the printed page.

function applyGeminiCorrections(
  htmlSegs: ArticleSegment[],
  geminiText: string,
): ArticleSegment[] {
  if (!geminiText || htmlSegs.length === 0) return htmlSegs;

  const result: ArticleSegment[] = [];

  for (let i = 0; i < htmlSegs.length; i++) {
    const seg = htmlSegs[i];

    // Use first 20 chars as anchor — short enough to survive minor OCR differences
    const searchKey = seg.title.slice(0, 20).trim();
    if (searchKey.length < 5) { result.push(seg); continue; }

    const titleIdx = geminiText.indexOf(searchKey);
    if (titleIdx === -1) { result.push(seg); continue; }

    // Skip past the title line
    const titleLineEnd = geminiText.indexOf("\n", titleIdx);
    if (titleLineEnd === -1) { result.push(seg); continue; }

    // Find where the next article starts in the Gemini text
    let endIdx = geminiText.length;
    for (let j = i + 1; j < htmlSegs.length; j++) {
      const nextKey = htmlSegs[j].title.slice(0, 20).trim();
      if (nextKey.length < 5) continue;
      const nextIdx = geminiText.indexOf(nextKey, titleLineEnd);
      if (nextIdx !== -1) { endIdx = nextIdx; break; }
    }

    const correctedContent = geminiText.slice(titleLineEnd + 1, endIdx).trim();
    if (correctedContent.length > 50) {
      console.log(`[gemini-merge] ✓ article ${i + 1} "${seg.title.slice(0, 30)}" — replaced ${seg.content.length} → ${correctedContent.length} chars`);
      result.push({ title: seg.title, content: correctedContent });
    } else {
      result.push(seg);
    }
  }

  return result;
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
      // Overlay Gemini-corrected text onto the HTML-parsed articles.
      // The HTML parser gives us correct article boundaries (titles/order);
      // Gemini gives us OCR-error-free body text.  Merging gets us both.
      if (segments.length > 0 && refinedText.length > 100) {
        segments = applyGeminiCorrections(segments, refinedText);
        console.log(`[stage3] Gemini corrections applied to article content`);
      }
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
    // 1. Raw OCR text (kept for audit / re-processing)
    await supabase.from("extracted_texts").insert({
      filename: originalName,
      mime_type: file.type || null,
      file_size: file.size,
      text: refinedText,
      language: "te",
      source: "ocr",
      confidence: GEMINI_KEY ? 0.95 : 0.8,
    }).then(({ error }) => {
      if (error) console.warn("[db] extracted_texts insert error:", error.message);
    });

    // 2. Newspaper row → get UUID back
    const pubDate = new Date().toISOString().split("T")[0];
    const { data: newsRow, error: newsErr } = await supabase
      .from("newspapers")
      .insert({
        title: effectiveDocumentTitle,
        publication_date: pubDate,
        language: "te",
        storage_url: storageUrl,
      })
      .select("id")
      .single();
    if (newsErr) console.warn("[db] newspaper insert error:", newsErr.message);
    const newspaperUuid: string | null = newsRow?.id ?? null;

    // 3. Individual articles — stored with full content and metadata
    let savedArticleIds: string[] = [];
    if (newspaperUuid && articles.length > 0) {
      const rows = articles.map((art, i) => ({
        newspaper_id: newspaperUuid,
        title: art.title,
        content_preview: art.preview,
        full_content: art.content,
        section: art.category,
        page_number: art.page ?? 1,
        processing_status: "ready",
        quality_score: GEMINI_KEY ? 0.95 : 0.80,
        position_json: {
          article_index: i + 1,
          document_type: documentType,
          reading_style: readingStyle,
          suggested_speaker: suggestedSpeaker,
          estimated_duration_seconds: art.estimatedDurationSeconds,
        },
      }));

      const { data: savedRows, error: artErr } = await supabase
        .from("articles")
        .insert(rows)
        .select("id");
      if (artErr) console.warn("[db] articles insert error:", artErr.message);
      else {
        savedArticleIds = (savedRows ?? []).map((r: { id: string }) => r.id);
        console.log(`[db] Saved ${savedArticleIds.length} articles → newspaper ${newspaperUuid}`);
      }
    }

    const processingTime = Math.round((Date.now() - startedAt) / 1000);
    console.log(`[done] ${articles.length} article(s), type=${documentType}, title="${effectiveDocumentTitle}", style=${readingStyle}, ${processingTime}s`);

    // Annotate each article in the response with its persisted DB uuid
    const articlesWithDbId = articles.map((art, i) => ({
      ...art,
      dbId: savedArticleIds[i] ?? null,
    }));

    return json({
      ok: true,
      newspaper: {
        id: newspaperUuid ?? `newspaper_${ts}`,
        title: effectiveDocumentTitle,
        date: pubDate,
        storageUrl,
      },
      articles: articlesWithDbId,
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
