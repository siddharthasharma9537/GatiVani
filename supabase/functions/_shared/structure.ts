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

import { PDFDocument } from "npm:pdf-lib@1.17.1";

// ── Page detail for vision calls ─────────────────────────────────────────────
// Gemini bills a PDF page at a FLAT token cost regardless of its physical size
// (258 on 2.5, 560 on 3.x) — roughly one 768x768 tile's worth of detail for an
// entire broadsheet. A Namaste Telangana page is a 2501x3900 300-DPI scan, so
// body text sits far below what the model can resolve, and even the display
// headline (జెన్-జీత్ గయా) doesn't survive.
//
// Fix: build ONE PDF whose first page is the whole page (global layout) and
// whose remaining pages are overlapping horizontal bands of that SAME page.
// The source is embedded once and drawn N+1 times, so the scan's bytes appear
// exactly once — measured on a real edition, 1637 KB in gives 1759 KB out at
// 2, 3 or 4 bands alike. That is (N+1)x the vision tokens for ~0 extra payload.
export const DETAIL_BANDS = 3;
const BAND_OVERLAP = 0.06; // bands overlap so a headline sitting on a cut survives whole

export async function detailPdf(
  pageBytes: Uint8Array,
  bands = DETAIL_BANDS,
): Promise<Uint8Array> {
  const src = await PDFDocument.load(pageBytes);
  const srcPage = src.getPage(0);
  const { width, height } = srcPage.getSize();

  const doc = await PDFDocument.create();
  const embedded = await doc.embedPage(srcPage);
  doc.addPage([width, height]).drawPage(embedded, { x: 0, y: 0, width, height });

  const band = height / bands;
  const pad = band * BAND_OVERLAP;
  for (let i = 0; i < bands; i++) {
    // PDF y-origin is bottom-left, so band 0 must be the TOP of the page.
    const bottom = Math.max(0, height - (i + 1) * band - pad);
    const top = Math.min(height, height - i * band + pad);
    doc.addPage([width, top - bottom])
      .drawPage(embedded, { x: 0, y: -bottom, width, height });
  }
  return await doc.save();
}

// Without this the model reads the payload as several DIFFERENT pages and
// reports the same article once per band.
const DETAIL_NOTE =
  `The attached PDF is ONE newspaper page. Its first page is the whole page; ` +
  `the remaining ${DETAIL_BANDS} pages are overlapping horizontal bands of that ` +
  `SAME page, top to bottom, shown larger so small print is legible. They are ` +
  `the same content at two magnifications — never treat a band as a separate ` +
  `page, and never report anything twice because it appears in both.\n\n`;

// Doc parts for a vision call, at band resolution when the source is a PDF.
// Returns null when there is nothing usable to show the model.
async function visionParts(
  fileBuffer: Uint8Array,
  mimeType: string,
): Promise<{ parts: unknown[]; note: string } | null> {
  const visual = (mimeType.startsWith("image/") || mimeType === "application/pdf") &&
    fileBuffer.length < 15 * 1024 * 1024;
  if (!visual) return null;
  const flat = {
    parts: [{ inline_data: { mime_type: mimeType, data: bytesToBase64(fileBuffer) } }],
    note: "",
  };
  if (mimeType !== "application/pdf") return flat;
  try {
    const detail = await detailPdf(fileBuffer);
    return {
      parts: [{ inline_data: { mime_type: "application/pdf", data: bytesToBase64(detail) } }],
      note: DETAIL_NOTE,
    };
  } catch (e) {
    console.warn("[structure] band tiling failed, sending flat page:", (e as Error).message);
    return flat;
  }
}

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
  "Opinion", "Business", "Sports", "Entertainment", "Health", "Sci-Tech",
  "Education", "Agriculture", "Crime", "Judiciary", "Devotional", "Trending",
  "News",
] as const;

interface Assignment {
  articles: Array<{
    article_id: string;
    category?: string;       // one of CATEGORIES — an enum label, not free text
    blocks: AssignedBlock[];
    // The ONLY free Telugu the model may emit — see headlineIsNovel.
    headline_text?: string;
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
  printedPage: number | null; // the page number printed on the page (vs PDF index)
}

// Sarvam tags the printed page number as <p class="page-number">6</p>. Editions
// often have cover/main pages before the numbered pages start, so the PDF index
// drifts from the real page number — prefer this when present.
export function extractPrintedPage(html: string): number | null {
  const m = html.match(/class="[^"]*page-number[^"]*"[^>]*>\s*([0-9]{1,3})/);
  if (!m) return null;
  const n = parseInt(m[1], 10);
  return n >= 1 && n <= 100 ? n : null;
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
- A page often runs a narrow COMMENTARY / opinion column down one edge, beside
  the lead story and usually about the same event. It is a SEPARATE article, and
  folding it into the news story beside it is a serious error. Tells: it has no
  dateline ("న్యూఢిల్లీ, జూలై 25:"); it argues rather than reports, using
  rhetorical questions, second person, or literary phrasing; it is set in its own
  narrow column running much of the page height, often in colour or a distinct
  face. Sharing a topic with the lead is NOT evidence it is the same item — a
  commentary piece beside a news story is precisely the case that looks related
  and is not.
- footnote blocks are photo captions ("caption") attached to the article whose photo
  they describe, or dropped as noise if decorative.
- If genuinely unsure where a block belongs, put it in "uncertain" with candidate
  article ids — do NOT guess silently.

For each article also set "category" — exactly one of:
International | National | State | District | Politics | Editorial | Opinion |
Business | Sports | Entertainment | Health | Sci-Tech | Education | Agriculture |
Crime | Judiciary | Devotional | Trending | News
(District = hyperlocal town/mandal news; State = state-level news; use News only
when nothing else fits.)
- Editorial = the paper's own unsigned leader/editorial — usually under a
  "సంపాదకీయం" header on the editorial page; there is normally just one or two.
- Opinion = signed op-eds, columns and analysis pieces (a named author byline,
  often on or beside the editorial page) expressing a viewpoint rather than
  reporting news. Letters to the editor are also Opinion.

One exception to "output ids, never Telugu" — "headline_text":
- Big display headlines are the thing OCR most often misses entirely: huge
  decorative type, frequently reversed out of a coloured block. If an article's
  MAIN printed headline is clearly visible in the page image but no manifest
  block contains it, transcribe it into "headline_text" EXACTLY as printed.
- Omit the field whenever the headline IS in the manifest. Never re-type a
  headline that already has a block, never invent one, never put body text or a
  summary there. If you are not certain of every character, omit it.
- A headline block may be present and still be the SMALLER secondary banner
  while the main headline above it was missed — that is exactly the case this
  field is for.

Return ONLY this JSON:
{"articles":[{"article_id":"a1","category":"Agriculture","headline_text":null,
 "blocks":[{"id":5,"role":"headline"},
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

export async function callGeminiJson(
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
  const vp = await visionParts(fileBuffer, mimeType);
  const docText = vp ? vp.note + manifestText : manifestText;

  // Quota-resilient ladder. Stage 2 (refineWithGemini) consumes flash quota with
  // the same document seconds earlier, so a 429 here is common — flash-lite has a
  // SEPARATE per-model quota bucket, and the text-only call is tiny.
  const configs: Array<{ model: string; parts: unknown[]; label: string }> = [];
  if (vp) {
    configs.push({ model: "gemini-2.5-flash", parts: [...vp.parts, { text: docText }], label: "flash+doc" });
    configs.push({ model: "gemini-2.5-flash-lite", parts: [...vp.parts, { text: docText }], label: "flash-lite+doc" });
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

// Sarvam frequently drops the trailing '.'/'।' after these closed-class
// finite verb forms (reported-speech/completion verbs that routinely end a
// Telugu news brief, e.g. "...వెంకటేష్ పాల్గొన్నారు" / "...అని తెలిపారు"),
// so require punctuation alone under-counts real sentence ends. Verified
// against production data: 5/147 ends_mid_sentence flags were this exact
// pattern (the rest were genuine — cross-page "...పేజీ 10లో" references or
// real truncation), so this is intentionally a narrow, closed list rather
// than a broad verb-suffix regex (which would over-match non-finite forms
// like "-ించి" that really do continue the sentence).
const VERB_FINAL_WORDS = "పాల్గొన్నారు|తెలిపారు|అన్నారు|పేర్కొన్నారు|వెల్లడించారు|" +
  "తెలియజేశారు|నిర్వహించారు|హెచ్చరించారు|సూచించారు|కోరారు|అభ్యర్థించారు|" +
  "తెలిపింది|పేర్కొంది|వెల్లడించింది";
const SENTENCE_FINAL = new RegExp(`(?:[.?!।॥…]['"’”)]?|(?:${VERB_FINAL_WORDS}))\\s*$`);
const OPENER = /^\s*[•▪●★☞✓?]|^\s*\d+[.)]\s/;
const TELUGU_START = /^[ఀ-౿]/;

function isContinuation(prev: string, next: string): boolean {
  if (SENTENCE_FINAL.test(prev)) return false;
  if (OPENER.test(next)) return false;
  return TELUGU_START.test(next.trim());
}

// [breaks], when set, is Layer 2's semantic judgment of which fragment
// (by original index in `parts`) starts a new paragraph — authoritative
// when present, since it comes from actually reading the fragments for
// meaning. Falls back to the regex heuristic (weak: effectively "does the
// previous fragment end with punctuation", since TELUGU_START matches
// almost any Telugu text) only when Layer 2 didn't judge this article —
// single-block articles, or a failed/skipped coherence call.
function stitch(parts: string[], breaks?: Set<number>): string[] {
  const out: string[] = [];
  parts.forEach((raw, i) => {
    const t = raw.trim();
    if (!t) return;
    const shouldMerge = out.length > 0 &&
      (breaks ? !breaks.has(i) : isContinuation(out[out.length - 1], t));
    if (shouldMerge) {
      out[out.length - 1] = out[out.length - 1].replace(/\s+$/, "") + " " + t;
    } else {
      out.push(t);
    }
  });
  return out;
}

// ── Printed article template ─────────────────────────────────────────────────
// A long newspaper article has a fixed printed shape: the headline, then a deck
// of three or four subheadings, then the body opening with a city+date dateline
// ("న్యూఢిల్లీ, జూలై 25:"), and — when the story runs on — a "continued on page
// N" marker as the very last thing in the column. The half that resumes on the
// inside page opens with its mirror, "మొదటిపేజీ తరువాయి".
//
// Those anchors are printed facts, so they beat the model's fragment ordering.
// Applying them after the coherence passes is what stops a body starting
// mid-story or ending on half a sentence: on the 2026-07-26 lead the two halves
// of one sentence ("…ఈ సుదీర్ఘ ఆందోళన ప్రభుత్వం" / "మధ్య మూడవ విడత చర్చలు…")
// came out in reverse order, which both truncated the article and tripped
// ends_mid_sentence into hiding it.
// A dateline can carry SEVERAL places before the date — a story filed from two
// districts runs "వరంగల్, మహబూబాబాద్, జూలై 25 (నమస్తే తెలంగాణ ప్రతినిధి):".
// Allowing only one place missed exactly that, so the template never fired on
// the front page's second lead and it kept opening with its side box.
const DATELINE_START =
  /^\s*(?:\([^)]{0,40}\)\s*)?[ఀ-౿]{2,20}(?:\s*,\s*[ఀ-౿]{2,20}){0,3}\s*,\s*[ఀ-౿]{2,12}\s*\d{1,2}\s*(?:\([^)]{0,40}\))?\s*:/;
const CONT_FROM_ANCHOR = /(?:\d{1,2}\s*(?:వ\s*)?పేజీ|మొదటి\s*పేజీ)\s*తరువాయి/;
const CONT_TO_TAIL =
  /(?:మిగతా|సశేషం|తరువాయి)\s*\(?\s*\d{1,2}\s*(?:వ\s*)?(?:పేజీలో|పేజీ|లో)|>\s*\d{1,2}\s*(?:వ\s*పేజీలో)?/;

function applyArticleTemplate(d: Draft): boolean {
  if (d.blocks.length < 2) return false;
  let changed = false;

  // Opening anchor: the dateline, or — on the inside-page half of a split
  // story — the "continued from page 1" header.
  let lead = d.blocks.findIndex((b) => CONT_FROM_ANCHOR.test(b.text));
  if (lead < 0) lead = d.blocks.findIndex((b) => DATELINE_START.test(b.text));
  if (lead > 0) {
    d.blocks.unshift(d.blocks.splice(lead, 1)[0]);
    changed = true;
  }

  // Closing anchor: the "continues on page N" marker ends the printed column,
  // so anything sorted after it is out of place.
  const tail = d.blocks.findIndex((b) => CONT_TO_TAIL.test(b.text));
  if (tail >= 0 && tail !== d.blocks.length - 1) {
    d.blocks.push(d.blocks.splice(tail, 1)[0]);
    changed = true;
  }
  return changed;
}

// ── [D] Validate ──────────────────────────────────────────────────────────────

// Leading dateline / byline — publication + city, journalistic metadata, not
// news content, so we don't narrate it. Forms: "ఈనాడు, చెన్నై:", "న్యూస్‌టుడే,
// కరీంనగర్:", "చెన్నై, ఈనాడు:".
const DATELINE_LEAD =
  /^\s*(?:[ఀ-౿]{2,24}\s*,\s*)?(?:ఈనాడు|న్యూస్\s?టుడే|సాక్షి)(?:\s*,\s*[ఀ-౿().\s]{2,40})?\s*:\s*/;

function stripLeadingDateline(s: string): string {
  return s.replace(DATELINE_LEAD, "").trimStart();
}

const AI_DESC = /ఈ చిత్రంలో|ఈ చిత్రం/;
const DATELINE = /[ఀ-౿()\s]{2,30}[,:]\s*న్యూ[సన]్?\s?టుడే|న్యూ[సన]్?\s?టుడే\s*[,:]/g;
const SIGNATURE = /-\s*న్యూ[సన]్?\s?టుడే/g;
const ATTRIBUTION_END = /-\s*[ఀ-౿][ఀ-౿\s,()]{2,40}$/;

// These flags are derived purely from the article's final text. Cross-page
// continuation stitching rewrites bodies AFTER insert (merging in the
// continuation half, stripping the "మిగతా Nవ పేజీలో" marker), so they have to
// be recomputed at that point — see recomputeReviewStatus in
// documents-process-edition. Every other flag describes the extraction process
// and stays as originally recorded.
export const TEXT_DERIVED_FLAGS = [
  "caption_leak", "fused_articles", "headline_missing", "ends_mid_sentence",
] as const;

// Flags that are worth recording but must not hide the article. Matched by
// prefix, since some carry a value suffix (low_coverage:0.86).
//   reordered    — the coherence pass REPAIRED fragment order. That is the
//                  pipeline working as designed, not a defect; gating on it
//                  withheld 25 of the 44 held-back articles in the 2026-07-26
//                  edition.
//   low_coverage — a PAGE-level statistic applied to every article on the page.
//                  Above the severe floor it says the page shed some
//                  characters, not that THIS article is bad. See the coverage
//                  block in extractArticlesStructured; severe_coverage_loss is
//                  deliberately absent from this list and still blocks.
//   headline_from_image — the headline was transcribed from the page image
//                  because OCR never produced it. This is model-written text
//                  reaching readers, so it is deliberately recorded; it does
//                  not block, because the alternative is shipping the article
//                  with a wrong headline or none at all, and the body remains
//                  OCR ground truth either way.
//   template_reordered — fragments were snapped to the printed article shape
//                  (dateline opens the body, continuation marker closes it).
//                  Like `reordered`, a repair rather than a defect.
//   teaser_box   — marks the row as a promo box rather than a story. A label,
//                  not a defect; see needsReview for what it exempts.
const NON_BLOCKING_FLAGS = [
  "reordered", "low_coverage", "headline_from_image", "template_reordered",
  "teaser_box",
];

// `teaser_box` marks a front-page promo pointing at a story printed elsewhere.
// It is SHORT and stops at a page pointer by design, so ends_mid_sentence — a
// check that assumes a full article — is meaningless for it and was withholding
// every such box. headline_missing still blocks: a teaser with no headline has
// nothing to list.
export function needsReview(flags: string[]): boolean {
  const teaser = flags.includes("teaser_box");
  return flags.some((f) => {
    if (NON_BLOCKING_FLAGS.some((n) => f.startsWith(n))) return false;
    if (teaser && f.startsWith("ends_mid_sentence")) return false;
    return true;
  });
}

export function validateArticle(a: { title: string; content: string }): string[] {
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

// A draft article before stitching — body kept as ordered fragments so the
// coherence passes can reorder / patch them.
interface Draft {
  title: string;
  subs: string[];
  caps: string[];
  category: string;
  blocks: Array<{ id: number; text: string }>;
  review: string[];
  // Positions (in `blocks`' final order) where Layer 2 judged a new paragraph
  // starts; everything else continues the previous fragment's sentence. Unset
  // when Layer 2 didn't run/answer for this article — stitch() then falls
  // back to the regex heuristic.
  breaks?: Set<number>;
}

// Gate on the one place the assignment step is allowed to emit Telugu.
//
// The index-only contract is what makes the BODY trustworthy: the model cannot
// hallucinate text it never had. But it also means a headline OCR missed can
// never enter the article — on the 2026-07-26 front page the printed headline
// was "జెన్-జీత్ గయా", Sarvam never emitted it as a block, and the article
// silently inherited the smaller pink sub-banner ("సర్కార్ డర్ గయా") instead.
// Sending the page at band resolution let the model READ the headline
// correctly; it had nowhere to put it.
//
// So the hole is deliberately headline-shaped: bodies stay index-only, and a
// transcription is accepted only when no manifest block already contains it —
// meaning it can add a headline OCR missed, but can never overwrite or restate
// one OCR captured.
function headlineIsNovel(candidate: string, blocks: Block[]): boolean {
  const squash = (s: string) => s.replace(/\s+/g, "");
  const c = squash(candidate);
  if (c.length < 4 || c.length > 160) return false;
  return !blocks.some((b) => squash(b.text).includes(c));
}

function frag(text: string, head = 60, tail = 30): string {
  return text.length <= head + tail
    ? `"${text}"`
    : `"${text.slice(0, head)}…" tail="…${text.slice(-tail)}"`;
}

function applyOrder(d: Draft, order: unknown): boolean {
  if (!Array.isArray(order) || order.length !== d.blocks.length) return false;
  if (new Set(order).size !== d.blocks.length) return false;
  if (!order.every((x) => typeof x === "number" && x >= 0 && x < d.blocks.length)) return false;
  const changed = order.some((x, k) => x !== k);
  d.blocks = (order as number[]).map((x) => d.blocks[x]);
  return changed;
}

// ── Layer 2: text coherence ──────────────────────────────────────────────────
// One cheap call per page. Reorders body fragments by MEANING (catches the
// within-column semantic mis-orders that string heuristics miss), flags
// narrative gaps, and splits out fragments that belong to a different story.
// Index-only: it permutes existing fragments, never edits text.
//
// Now sees the page image and 160+60 chars per fragment. At 60+30 text-only it
// was judging topical membership from ~90-character snippets with no view of
// the layout, and missed a 1,965-char foreign column sitting inside a
// front-page lead — it reordered that article and reported it coherent.
async function coherencePass(
  drafts: Draft[], fileBuffer: Uint8Array, mimeType: string, geminiKey: string,
): Promise<void> {
  const lines: string[] = [];
  drafts.forEach((d, i) => {
    if (d.blocks.length < 2) return;
    lines.push(`# Article ${i}: ${d.title.slice(0, 40)}`);
    d.blocks.forEach((b, j) => lines.push(`  [${j}] ${frag(b.text, 160, 60)}`));
  });
  if (!lines.length) return;
  const prompt =
`The page image is provided — use it to see which fragments physically belong to
the same article, and in what order a reader would take them.

Each article below is a list of OCR text fragments in their CURRENT order.
Newspapers split stories across columns, so fragments can be out of reading order.
For each article decide if the fragments read as ONE coherent story in the right
order, judging by MEANING (does each fragment continue the previous idea?).

Also decide, for the CORRECTED order, which fragments start a NEW paragraph vs.
continue the previous fragment's sentence/thought (common when a sentence was
split across two OCR blocks — e.g. a column or line break landed mid-sentence).

Also check topic consistency: does every fragment actually belong to THIS
story, or does one look like it drifted in from a different, unrelated
article (a sign the earlier assignment step grouped it with the wrong
story) — different subject, different people/place, reads like an
unconnected news item rather than a continuation of this one.

Return ONLY JSON:
{"articles":[{"i":0,"order":[2,0,1],"gap":false,"paragraph_breaks":[0,2],"misplaced":[1]}]}
RULES:
- "order" = that article's fragment indices in correct reading order. It MUST be a
  permutation of the existing indices — never invent, drop, or edit text. Omit it
  if already correct.
- "gap": true ONLY if a piece is clearly missing (a narrative jump no reorder fixes).
- "paragraph_breaks" = positions (0-indexed, in the CORRECTED order) where a new
  paragraph starts. Position 0 is always a break implicitly — no need to include
  it. Any position NOT listed continues the previous fragment's sentence with no
  paragraph break. Include this whenever you can judge it with confidence; omit
  the whole field for an article only if genuinely unsure.
- "misplaced" = positions (0-indexed, in the CORRECTED order) of fragments that
  don't topically belong in this article. Only include a position when you're
  genuinely confident it's unrelated — being out of order or hard to follow is
  NOT the same as being misplaced. Omit or leave empty when everything fits.
  A run of fragments that reads as a self-contained column or commentary piece
  in the middle of a news story is the clearest case: list all of them.

${lines.join("\n")}`;
  const vp = await visionParts(fileBuffer, mimeType);
  const parts = vp ? [...vp.parts, { text: vp.note + prompt }] : [{ text: prompt }];
  const { status, text } = await callGeminiJson("gemini-2.5-flash-lite", parts, geminiKey);
  if (status !== 200) return;
  const data = JSON.parse((text.match(/\{[\s\S]*\}/) ?? ["{}"])[0]) as {
    articles?: Array<{
      i: number; order?: number[]; gap?: boolean;
      paragraph_breaks?: number[]; misplaced?: number[];
    }>;
  };
  const spawned: Draft[] = [];
  for (const r of data.articles ?? []) {
    const d = drafts[r.i];
    if (!d) continue;
    if (applyOrder(d, r.order)) d.review.push("reordered");
    if (r.gap) d.review.push("gap_suspected");
    if (Array.isArray(r.paragraph_breaks)) {
      d.breaks = new Set(
        r.paragraph_breaks.filter(
          (x) => typeof x === "number" && x >= 0 && x < d.blocks.length,
        ),
      );
    }
    // Misplaced fragments used to only raise a review flag while STAYING in the
    // article — so a whole foreign column could sit inside the lead story and
    // still be narrated as part of it (real case: a 1,965-char opinion column
    // wedged into a front-page lead between its own body and its page-7
    // continuation). Detection without remediation is not a safeguard. Split
    // them into their own draft instead; it lands headless, so validateArticle
    // flags headline_missing and it is held for review rather than read aloud
    // under someone else's headline.
    const mis = (r.misplaced ?? []).filter(
      (x) => typeof x === "number" && x >= 0 && x < d.blocks.length,
    );
    if (mis.length && mis.length < d.blocks.length) {
      const misSet = new Set(mis);
      const moved = d.blocks.filter((_, j) => misSet.has(j));
      d.blocks = d.blocks.filter((_, j) => !misSet.has(j));
      // Positions shifted, so Layer 2's paragraph_breaks no longer line up.
      d.breaks = undefined;
      d.review.push("topic_mismatch");
      spawned.push({
        title: "", subs: [], caps: [], category: d.category,
        blocks: moved, review: ["split_from_fused"],
      });
      console.log(`[structure] split ${moved.length} misplaced fragment(s) out of article ${r.i}`);
    }
  }
  drafts.push(...spawned);
}

// ── Layer 3: vision recovery ─────────────────────────────────────────────────
// Runs only for articles Layer 2 flagged as gapped. Uses the page IMAGE as
// ground truth to fix order and transcribe text that OCR missed. Recovered text
// is model-transcribed (not Sarvam ground truth) so the article is flagged
// `vision_recovered` for review.
async function visionPass(
  drafts: Draft[], fileBuffer: Uint8Array, mimeType: string, geminiKey: string,
): Promise<void> {
  const targets = drafts
    .map((d, i) => ({ d, i }))
    .filter((t) => t.d.review.includes("gap_suspected"));
  if (!targets.length) return;
  const vp = await visionParts(fileBuffer, mimeType);
  if (!vp) return;

  const lines: string[] = [];
  for (const { d, i } of targets) {
    lines.push(`# Article ${i}: ${d.title.slice(0, 40)}`);
    d.blocks.forEach((b, j) => lines.push(`  [${j}] ${frag(b.text)}`));
  }
  const prompt =
`The page IMAGE is provided. The articles below were flagged as possibly missing
text or out of order. Using the image as ground truth, return ONLY JSON:
{"articles":[{"i":0,"order":[...],"inserts":[{"after":1,"text":"<missing Telugu from image>"}]}]}
RULES:
- "order": correct reading order of the existing fragment indices (a permutation).
- "inserts": ONLY text visibly present in the image but missing from the fragments.
  Transcribe EXACTLY from the image — never paraphrase or invent. "after" is the
  fragment index it follows (-1 = very start).
- If nothing is missing and order is fine, return empty arrays.

${lines.join("\n")}`;
  const { status, text } = await callGeminiJson(
    "gemini-2.5-flash-lite",
    [...vp.parts, { text: vp.note + prompt }],
    geminiKey,
  );
  if (status !== 200) return;
  const data = JSON.parse((text.match(/\{[\s\S]*\}/) ?? ["{}"])[0]) as {
    articles?: Array<{ i: number; order?: number[]; inserts?: Array<{ after: number; text: string }> }>;
  };
  for (const r of data.articles ?? []) {
    const d = drafts[r.i];
    if (!d) continue;
    // Reordering (or the insert below) reshapes `blocks`, which invalidates
    // any position-based `breaks` Layer 2 set — they'd now point at the
    // wrong fragments. Drop them; stitch() falls back to the regex
    // heuristic for this article rather than apply stale positions.
    if (applyOrder(d, r.order)) d.breaks = undefined;
    const inserts = (r.inserts ?? []).filter(
      (x) => typeof x?.text === "string" && x.text.trim().length >= 4);
    if (!inserts.length) continue;
    const after = new Map<number, string[]>();
    for (const ins of inserts) {
      const list = after.get(ins.after) ?? [];
      list.push(ins.text.trim());
      after.set(ins.after, list);
    }
    const out: Array<{ id: number; text: string }> = [];
    for (const t of after.get(-1) ?? []) out.push({ id: -1, text: t });
    d.blocks.forEach((b, j) => {
      out.push(b);
      for (const t of after.get(j) ?? []) out.push({ id: -1, text: t });
    });
    d.blocks = out;
    d.breaks = undefined;
    d.review = d.review.filter((f) => f !== "gap_suspected");
    d.review.push("vision_recovered");
  }
}

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

  // Build drafts (body kept as ordered fragments — stitching deferred until
  // after the coherence passes can reorder / patch them).
  const drafts: Draft[] = [];
  let missingSeq = 0;
  let bodyTotal = 0;
  let imageHeadlines = 0;
  for (const art of assignment.articles ?? []) {
    let title = "";
    const subs: string[] = [];
    const caps: string[] = [];
    // [seq, col, row, id, text] — see the sort below for why col/row are here.
    const bodyEntries: Array<[number, number, number, number, string]> = [];
    for (const blk of art.blocks ?? []) {
      const b = byId.get(blk.id);
      if (!b) continue;
      if (blk.role === "headline") title = b.text;
      else if (blk.role === "subheading") subs.push(b.text);
      else if (blk.role === "caption") caps.push(b.text);
      else if (blk.role === "body") {
        if (blk.seq === undefined) missingSeq++;
        bodyTotal++;
        bodyEntries.push([blk.seq ?? 1e6, b.col, b.row, blk.id, b.text]);
      }
      // role "table": excluded from spoken body
    }
    // "seq" is optional in the assignment contract, so when the model omits it
    // every block collapses to 1e6 and the tiebreaker decides the whole reading
    // order. That tiebreaker used to be block id. parseBlocks walks
    // rows.forEach(cols.forEach(...)), so ids are column-major WITHIN a row
    // band but restart at the next band — an article spanning several bands
    // gets every column of band 0, then every column of band 1, which reads
    // across the page instead of down it. That is the zigzag.
    // Column-major (col, then row) is how a newspaper is actually read, so an
    // unanswered seq now degrades to the right order instead of the worst one.
    bodyEntries.sort((x, y) => x[0] - y[0] || x[1] - y[1] || x[2] - y[2] || x[3] - y[3]);
    const category = (CATEGORIES as readonly string[]).includes(art.category ?? "")
      ? art.category!
      : "";

    // Headline the model read off the page that OCR never produced. Accepted
    // only if no block already contains it, so it can fill a missing headline
    // or supersede a smaller banner OCR mistook for the main one — but can
    // never overwrite a headline OCR actually captured.
    const review: string[] = [];
    const fromImage = (art.headline_text ?? "").trim();
    if (fromImage && headlineIsNovel(fromImage, blocks)) {
      // Keep whatever OCR did find; it is usually the real secondary banner.
      if (title) subs.unshift(title);
      title = fromImage;
      review.push("headline_from_image");
      imageHeadlines++;
    }

    drafts.push({
      title, subs, caps, category, review,
      blocks: bodyEntries.map((e) => ({ id: e[3], text: e[4] })),
    });
  }
  if (imageHeadlines) {
    console.log(`[structure] ${imageHeadlines} headline(s) transcribed from the page image`);
  }
  if (bodyTotal) {
    console.log(`[structure] seq missing on ${missingSeq}/${bodyTotal} body blocks` +
      `${missingSeq / bodyTotal > 0.2 ? " — ordering is leaning on the column-major fallback" : ""}`);
  }

  // Layer 2 (text coherence) → Layer 3 (vision, only for flagged gaps). Both
  // non-fatal: any failure leaves the structure-engine order untouched.
  if (geminiKey) {
    try { await coherencePass(drafts, fileBuffer, mimeType, geminiKey); }
    catch (e) { console.warn("[structure] L2 coherence failed:", (e as Error).message); }
    if (drafts.some((d) => d.review.includes("gap_suspected"))) {
      try { await visionPass(drafts, fileBuffer, mimeType, geminiKey); }
      catch (e) { console.warn("[structure] L3 vision failed:", (e as Error).message); }
    }
  }

  // Last word on ordering goes to the printed template, not to any model pass:
  // the dateline opens the body and the "continued on page N" marker closes it.
  let templated = 0;
  for (const d of drafts) {
    if (!applyArticleTemplate(d)) continue;
    d.breaks = undefined; // positions no longer line up with the fragments
    d.review.push("template_reordered");
    templated++;
  }
  if (templated) {
    console.log(`[structure] ${templated} article(s) reordered to the printed template`);
  }

  const articles: StructuredArticle[] = [];
  for (const d of drafts) {
    const paragraphs = stitch(d.blocks.map((b) => b.text), d.breaks);
    if (paragraphs.length) paragraphs[0] = stripLeadingDateline(paragraphs[0]);
    const article: StructuredArticle = {
      title: d.title || d.subs[0] || "",
      content: paragraphs.join("\n\n"),
      subheadings: d.subs,
      captions: d.caps,
      category: d.category,
      review: [],
    };
    if (article.content.length < 60) continue;  // skip empty/fragment articles
    article.review = [...d.review, ...validateArticle(article)];
    articles.push(article);
  }

  // Coverage: how much of the OCR'd content survived into articles. A low value
  // means the model dropped content blocks (sent them to `drop` instead of an
  // article) — a silent content-loss detector. NB: this CANNOT catch text that
  // Sarvam never OCR'd, nor a semantic mis-order within a column (that needs an
  // LLM coherence pass) — it only catches dropped *blocks*.
  const isContentCls = (c: string) =>
    c === "paragraph" || c === "headline" || c === "section-title";
  const ocrChars = blocks.filter((b) => isContentCls(b.cls))
    .reduce((s, b) => s + b.text.length, 0);
  const keptChars = articles.reduce(
    (s, a) => s + a.content.length + a.title.length + a.subheadings.join("").length, 0);
  // Coverage is a PAGE-level statistic, so withholding every article on the
  // page because the page as a whole shed some characters punished articles
  // that were individually fine — it blacked out pages 8 and 9 of the
  // 2026-07-26 edition entirely (13 articles) at 0.79 and 0.86. Showing a page
  // that lost a fraction of its characters beats showing nothing, and genuinely
  // damaged articles are still caught by the per-article checks. So this is
  // informational above the floor and blocking only below it, where the page
  // really is too broken to serve.
  const coverage = ocrChars ? keptChars / ocrChars : 1;
  if (coverage < 0.6) {
    for (const a of articles) a.review.push(`severe_coverage_loss:${coverage.toFixed(2)}`);
  } else if (coverage < 0.9) {
    for (const a of articles) a.review.push(`low_coverage:${coverage.toFixed(2)}`);
  }

  const flaggedCount = articles.filter((a) => a.review.length > 0).length;
  console.log(
    `[structure] ${articles.length} articles, ${flaggedCount} flagged, ` +
      `coverage=${coverage.toFixed(2)}, ${assignment.uncertain?.length ?? 0} uncertain`,
  );
  return {
    articles,
    uncertainCount: assignment.uncertain?.length ?? 0,
    flaggedCount,
    printedPage: extractPrintedPage(rawOcrHtml),
  };
}
