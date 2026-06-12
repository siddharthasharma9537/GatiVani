// Structured newspaper extraction engine.
// TypeScript port of gativani-extraction/CHALLENGE/solution/{pipeline,validate}.py
// (validated: 15 correct articles vs 4 from the legacy parser on the same page).
//
// Design (see gativani-extraction/CHALLENGE/PLAN.md):
//   [A] atomize  — parse Sarvam HTML nesting into ordered atomic blocks.
//                  Block text is character ground truth and is never edited.
//   [B] assign   — Gemini sees the original document + a numbered block manifest
//                  and returns ONLY indices {article_id, role, seq}. The model
//                  never emits Telugu → hallucination impossible by construction.
//   [C] assemble — deterministic grouping + Telugu mid-sentence fragment stitching.
//   [D] validate — deterministic checks; failures become review flags, not crashes.

// ── Types ─────────────────────────────────────────────────────────────────────

export interface Block {
  id: number;
  row: number;   // index of multi-column-row in document order; -1 = outside rows
  col: number;   // index of column-block within its row; -1 = outside
  cls: string;   // headline | section-title | paragraph | advertisement | footnote | table
  text: string;  // ground truth — never edited downstream
}

interface AssignedBlock {
  id: number;
  role: "headline" | "subheading" | "body" | "caption" | "table";
  seq?: number;
  continues_block?: number;
}

export const CATEGORIES = [
  "International", "National", "State", "District", "Politics", "Editorial",
  "Business", "Sports", "Entertainment", "Health", "Sci-Tech", "Education",
  "Agriculture", "Crime", "Judiciary", "Devotional", "Trending", "News",
] as const;

interface Assignment {
  articles: Array<{
    article_id: string;
    category?: string;       // one of CATEGORIES — an enum label, not free text
    blocks: AssignedBlock[];
  }>;
  drop?: Array<{ id: number; reason: string }>;
  uncertain?: Array<{ id: number; candidates?: string[]; reason?: string }>;
}

export interface StructuredArticle {
  title: string;
  content: string;          // body paragraphs joined with \n\n
  subheadings: string[];
  captions: string[];
  category: string;         // from CATEGORIES; "" if model omitted it
  review: string[];         // validation flags; empty = clean
}

export interface StructuredResult {
  articles: StructuredArticle[];
  uncertainCount: number;
  flaggedCount: number;
}

// ── [A] Atomize: Sarvam HTML → blocks ────────────────────────────────────────
// Reuses the depth-tracking div pairing approach (lazy regex breaks on nesting).

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

function findDivsByClass(html: string, classSubstr: string): Array<{ start: number; content: string; end: number }> {
  const results: Array<{ start: number; content: string; end: number }> = [];
  let i = 0;
  while (i < html.length) {
    const tagStart = html.indexOf("<div", i);
    if (tagStart === -1) break;
    const tagEnd = html.indexOf(">", tagStart);
    if (tagEnd === -1) break;
    const openTag = html.slice(tagStart, tagEnd + 1);
    if (openTag.includes(classSubstr)) {
      const { content, end } = extractDivContent(html, tagEnd + 1);
      results.push({ start: tagStart, content, end });
      i = end;
    } else {
      i = tagEnd + 1;
    }
  }
  return results;
}

function stripTags(html: string): string {
  return html
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<\/(td|th|tr)>/gi, " ")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ").replace(/&#\d+;/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function extractElements(scope: string, row: number, col: number, blocks: Block[]): void {
  // div.table first (may contain nested markup the element regex would mangle)
  const tables = findDivsByClass(scope, 'class="table"');
  let cleaned = scope;
  for (const t of tables) {
    const text = stripTags(t.content);
    if (text) blocks.push({ id: -1, row, col, cls: "table", text });
  }
  // remove table spans so the element regex doesn't re-match their contents
  for (let k = tables.length - 1; k >= 0; k--) {
    cleaned = cleaned.slice(0, tables[k].start) + cleaned.slice(tables[k].end);
  }

  const elementRe = /<(h[1-4]|p|aside)([^>]*)>([\s\S]*?)<\/\1>/gi;
  let m: RegExpExecArray | null;
  while ((m = elementRe.exec(cleaned)) !== null) {
    const attrs = m[2];
    const cls = (attrs.match(/class="([^"]*)"/) ?? [])[1] ?? "";
    const base = cls.split(/\s+/)[0] || m[1];
    if (base === "page-number" || base === "header" || base === "footer") continue;
    const text = stripTags(m[3]);
    if (!text) continue;
    blocks.push({ id: -1, row, col, cls: base, text });
  }
}

export function parseBlocks(html: string): Block[] {
  const doc = html
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
    .replace(/src="data:image[^"]*"/gi, 'src=""')
    .replace(/<header[^>]*>[\s\S]*?<\/header>/gi, "");

  const blocks: Block[] = [];
  const rows = findDivsByClass(doc, "multi-column-row");
  rows.forEach((rowDiv, r) => {
    const cols = findDivsByClass(rowDiv.content, "column-block");
    cols.forEach((colDiv, c) => extractElements(colDiv.content, r, c, blocks));
  });

  // Elements outside any row (Sarvam emits photo-caption footnotes after the rows)
  let remainder = doc;
  for (let k = rows.length - 1; k >= 0; k--) {
    remainder = remainder.slice(0, rows[k].start) + remainder.slice(rows[k].end);
  }
  extractElements(remainder, -1, -1, blocks);

  blocks.forEach((b, i) => (b.id = i));
  return blocks;
}

// ── [B] Assignment: Gemini, index-only output ─────────────────────────────────

function manifest(blocks: Block[], head = 72, tail = 32): string {
  return blocks
    .map((b) => {
      const t = b.text;
      const snippet =
        t.length <= head + tail
          ? `"${t}"`
          : `"${t.slice(0, head)}…" tail="…${t.slice(-tail)}"`;
      return `[${b.id}] row=${b.row} col=${b.col} cls=${b.cls} ${snippet}`;
    })
    .join("\n");
}

const ASSIGN_PROMPT = `You are reconstructing the human reading structure of a Telugu newspaper page.

You are given the original document (image/PDF) and a MANIFEST of atomic text blocks
extracted by OCR. Each block has an id, its (row, col) position in the OCR's column
layout, a CSS class hint (headline / section-title / paragraph / advertisement /
footnote / table), and the first/last characters of its text.

Your job is STRUCTURE ONLY. Output ids — never any Telugu text.

Assign every block id to exactly one of:
- an article, with role: "headline" | "subheading" | "body" | "caption" | "table"
- the drop list, with reason: "ad" | "masthead" | "noise"

Rules:
- An article = one news item a human would read as a unit. Use the page image to decide
  boundaries: a column-block may contain several articles; an article's body may
  continue in a different row/column (follow the visual flow).
- "seq" gives body reading order within the article (1, 2, 3, …). If a block visually
  continues another block mid-sentence, add "continues_block": <id>.
- class hints can be wrong (a headline may be tagged section-title; a news brief may be
  tagged advertisement). Trust the page over the hint.
- footnote blocks are photo captions ("caption") attached to the article whose photo
  they describe, or dropped as noise if decorative.
- If genuinely unsure where a block belongs, put it in "uncertain" with candidate
  article ids — do NOT guess silently.

For each article also set "category" — exactly one of:
International | National | State | District | Politics | Editorial | Business |
Sports | Entertainment | Health | Sci-Tech | Education | Agriculture | Crime |
Judiciary | Devotional | Trending | News
(District = hyperlocal town/mandal news; State = state-level news; use News only
when nothing else fits.)

Return ONLY this JSON:
{"articles":[{"article_id":"a1","category":"Agriculture","blocks":[{"id":5,"role":"headline"},
 {"id":7,"role":"body","seq":1},{"id":9,"role":"body","seq":2,"continues_block":7}]}],
 "drop":[{"id":3,"reason":"masthead"}],
 "uncertain":[{"id":41,"candidates":["a4","a5"],"reason":"…"}]}

MANIFEST:
`;

// Models sometimes echo CSS class hints as roles — normalize instead of rejecting.
const ROLE_ALIASES: Record<string, AssignedBlock["role"] | "drop"> = {
  "headline": "headline", "title": "headline",
  "subheading": "subheading", "section-title": "subheading", "subtitle": "subheading",
  "sub-heading": "subheading", "subhead": "subheading", "kicker": "subheading",
  "body": "body", "paragraph": "body", "text": "body",
  "caption": "caption", "footnote": "caption", "figure": "caption", "image": "caption",
  "table": "table",
  "ad": "drop", "advertisement": "drop", "masthead": "drop", "noise": "drop",
};

function checkAssignment(blocks: Block[], data: Assignment): string {
  const ids = new Set(blocks.map((b) => b.id));
  const seen = new Map<number, string>();
  for (const art of data.articles ?? []) {
    const kept: AssignedBlock[] = [];
    for (const blk of art.blocks ?? []) {
      if (!ids.has(blk.id)) return `unknown id ${blk.id}`;
      if (seen.has(blk.id)) return `id ${blk.id} assigned twice`;
      const norm = ROLE_ALIASES[(blk.role ?? "").toLowerCase()];
      if (!norm) return `bad role "${blk.role}" on id ${blk.id}`;
      seen.set(blk.id, art.article_id);
      if (norm === "drop") {
        data.drop = data.drop ?? [];
        data.drop.push({ id: blk.id, reason: "noise" });
        seen.set(blk.id, "drop");
        continue;
      }
      blk.role = norm;
      kept.push(blk);
    }
    art.blocks = kept;
  }
  for (const d of data.drop ?? []) {
    if (seen.has(d.id) && seen.get(d.id) !== "drop") {
      return `id ${d.id} both dropped and assigned`;
    }
    seen.set(d.id, "drop");
  }
  for (const u of data.uncertain ?? []) if (!seen.has(u.id)) seen.set(u.id, "uncertain");
  const missing = [...ids].filter((i) => !seen.has(i));
  if (missing.length > 3) return `unassigned ids: ${missing.slice(0, 20).join(",")}`;
  if (missing.length) {
    // tolerate a few strays: route them to human review instead of failing the page
    data.uncertain = data.uncertain ?? [];
    for (const id of missing) {
      data.uncertain.push({ id, reason: "not assigned by model — auto-routed to review" });
    }
    console.log(`[structure] ${missing.length} unassigned block(s) auto-routed to uncertain`);
  }
  return "";
}

function bytesToBase64(bytes: Uint8Array): string {
  const CHUNK = 8192;
  let binary = "";
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, Math.min(i + CHUNK, bytes.length)));
  }
  return btoa(binary);
}

async function callGeminiJson(
  model: string,
  parts: unknown[],
  geminiKey: string,
): Promise<{ status: number; text: string }> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiKey}`;
  let resp: Response | null = null;
  // retry transient 429 (quota window) and 5xx with spaced waits
  for (const backoff of [0, 15000]) {
    if (backoff) await new Promise((r) => setTimeout(r, backoff));
    resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts }],
        generationConfig: {
          maxOutputTokens: 32000,
          responseMimeType: "application/json",
          // thinking eats the output budget on 2.5 and truncates the JSON
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
      signal: AbortSignal.timeout(60_000),
    });
    if (resp.status !== 429 && resp.status < 500) break;
  }
  if (!resp) return { status: 0, text: "" };
  const status = resp.status;
  if (!resp.ok) {
    await resp.body?.cancel();
    return { status, text: "" };
  }
  const data = await resp.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  return {
    status,
    text: (data.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? "").join(""),
  };
}

async function assignWithGemini(
  blocks: Block[],
  fileBuffer: Uint8Array,
  mimeType: string,
  geminiKey: string,
): Promise<Assignment> {
  const manifestText = ASSIGN_PROMPT + manifest(blocks);
  const visual = (mimeType.startsWith("image/") || mimeType === "application/pdf") &&
    fileBuffer.length < 15 * 1024 * 1024;
  const docPart = visual
    ? { inline_data: { mime_type: mimeType, data: bytesToBase64(fileBuffer) } }
    : null;

  // Quota-resilient ladder. Stage 2 (refineWithGemini) consumes flash quota with
  // the same document seconds earlier, so a 429 here is common — flash-lite has a
  // SEPARATE per-model quota bucket, and the text-only call is tiny.
  const configs: Array<{ model: string; parts: unknown[]; label: string }> = [];
  if (docPart) {
    configs.push({ model: "gemini-2.5-flash", parts: [docPart, { text: manifestText }], label: "flash+doc" });
    configs.push({ model: "gemini-2.5-flash-lite", parts: [docPart, { text: manifestText }], label: "flash-lite+doc" });
  }
  configs.push({ model: "gemini-2.5-flash", parts: [{ text: manifestText }], label: "flash text-only" });
  configs.push({ model: "gemini-2.5-flash-lite", parts: [{ text: manifestText }], label: "flash-lite text-only" });

  let lastErr = "";
  for (const cfg of configs) {
    let correction = "";
    for (let attempt = 0; attempt < 2; attempt++) {
      const parts = correction
        ? [...cfg.parts, { text: `Your previous answer was invalid: ${correction}. Return corrected JSON only.` }]
        : cfg.parts;
      const { status, text } = await callGeminiJson(cfg.model, parts, geminiKey);
      if (status !== 200) {
        lastErr = `${cfg.label}: HTTP ${status}`;
        break;  // try next config (different model/payload → different quota)
      }
      try {
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        const parsed = JSON.parse(jsonMatch ? jsonMatch[0] : text) as Assignment;
        const err = checkAssignment(blocks, parsed);
        if (!err) {
          console.log(`[structure] assignment via ${cfg.label}`);
          return parsed;
        }
        correction = err;
        lastErr = `${cfg.label}: ${err}`;
      } catch (e) {
        correction = `JSON parse error: ${(e as Error).message}`;
        lastErr = `${cfg.label}: ${correction}`;
      }
    }
  }
  throw new Error(`assignment failed: ${lastErr}`);
}

// ── [C] Assemble: deterministic grouping + fragment stitching ────────────────

const SENTENCE_FINAL = /[.?!।॥…]['"’”)]?\s*$/;
const OPENER = /^\s*[•▪●★☞✓?]|^\s*\d+[.)]\s/;
const TELUGU_START = /^[ఀ-౿]/;

function isContinuation(prev: string, next: string): boolean {
  if (SENTENCE_FINAL.test(prev)) return false;
  if (OPENER.test(next)) return false;
  return TELUGU_START.test(next.trim());
}

function stitch(parts: string[]): string[] {
  const out: string[] = [];
  for (const raw of parts) {
    const t = raw.trim();
    if (!t) continue;
    if (out.length && isContinuation(out[out.length - 1], t)) {
      out[out.length - 1] = out[out.length - 1].replace(/\s+$/, "") + " " + t;
    } else {
      out.push(t);
    }
  }
  return out;
}

// ── [D] Validate ──────────────────────────────────────────────────────────────

const AI_DESC = /ఈ చిత్రంలో|ఈ చిత్రం/;
const DATELINE = /[ఀ-౿()\s]{2,30}[,:]\s*న్యూ[సన]్?\s?టుడే|న్యూ[సన]్?\s?టుడే\s*[,:]/g;
const SIGNATURE = /-\s*న్యూ[సన]్?\s?టుడే/g;
const ATTRIBUTION_END = /-\s*[ఀ-౿][ఀ-౿\s,()]{2,40}$/;

function validateArticle(a: StructuredArticle): string[] {
  const flags: string[] = [];
  const body = a.content;
  if (AI_DESC.test(body)) flags.push("caption_leak");
  const datelines = body.match(DATELINE) ?? [];
  const signatures = body.match(SIGNATURE) ?? [];
  if (datelines.length + signatures.length > 2 || datelines.length > 1) {
    flags.push(`fused_articles:${datelines.length}d+${signatures.length}s`);
  }
  if (!a.title.trim()) flags.push("headline_missing");
  const paras = body.split("\n\n").filter((p) => p.trim());
  const last = paras[paras.length - 1] ?? "";
  if (last && !SENTENCE_FINAL.test(last) && !ATTRIBUTION_END.test(last)) {
    flags.push("ends_mid_sentence");
  }
  return flags;
}

// ── Entry point ───────────────────────────────────────────────────────────────

export async function extractArticlesStructured(
  rawOcrHtml: string,
  fileBuffer: Uint8Array,
  mimeType: string,
  geminiKey: string,
): Promise<StructuredResult> {
  const blocks = parseBlocks(rawOcrHtml);
  if (blocks.length < 5) throw new Error(`too few blocks (${blocks.length})`);
  console.log(`[structure] atomized ${blocks.length} blocks`);

  const assignment = await assignWithGemini(blocks, fileBuffer, mimeType, geminiKey);
  const byId = new Map(blocks.map((b) => [b.id, b]));

  const articles: StructuredArticle[] = [];
  for (const art of assignment.articles ?? []) {
    let title = "";
    const subs: string[] = [];
    const caps: string[] = [];
    const bodyEntries: Array<[number, number, string]> = [];
    for (const blk of art.blocks ?? []) {
      const b = byId.get(blk.id);
      if (!b) continue;
      if (blk.role === "headline") title = b.text;
      else if (blk.role === "subheading") subs.push(b.text);
      else if (blk.role === "caption") caps.push(b.text);
      else if (blk.role === "body") bodyEntries.push([blk.seq ?? 1e6, blk.id, b.text]);
      // role "table": excluded from spoken body
    }
    bodyEntries.sort((x, y) => x[0] - y[0] || x[1] - y[1]);
    const paragraphs = stitch(bodyEntries.map((e) => e[2]));
    const category = (CATEGORIES as readonly string[]).includes(art.category ?? "")
      ? art.category!
      : "";
    const article: StructuredArticle = {
      title: title || subs[0] || "",
      content: paragraphs.join("\n\n"),
      subheadings: subs,
      captions: caps,
      category,
      review: [],
    };
    if (article.content.length < 60) continue;  // skip empty/fragment articles
    article.review = validateArticle(article);
    articles.push(article);
  }

  const flaggedCount = articles.filter((a) => a.review.length > 0).length;
  console.log(
    `[structure] ${articles.length} articles, ${flaggedCount} flagged, ` +
      `${assignment.uncertain?.length ?? 0} uncertain`,
  );
  return {
    articles,
    uncertainCount: assignment.uncertain?.length ?? 0,
    flaggedCount,
  };
}
