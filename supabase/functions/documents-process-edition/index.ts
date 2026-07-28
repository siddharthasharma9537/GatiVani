// Async multi-page edition processing.
//
// A full Telugu daily (18–24 pages) cannot run synchronously: the per-page
// pipeline (Sarvam OCR ~20s + structure assignment ~20s) times a 20-page
// edition exceeds any single invocation budget. Instead:
//
//   POST multipart {document}  → store PDF, count pages, create processing_jobs
//                                row, fire page-1 continuation, return job_id
//   POST json {job_id, page}   → (internal, service-role only) process ONE page,
//                                update progress, fire next page
//   client polls               → GET rest/v1/processing_jobs?id=eq.{job_id}
//
// Articles from every page aggregate under one newspapers row with correct
// page_number. Page failures are recorded in failed_pages and skipped — a bad
// page never kills the edition.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument } from "npm:pdf-lib@1.17.1";
import {
  callGeminiJson,
  detailPdf,
  extractArticlesStructured,
  needsReview,
  TEXT_DERIVED_FLAGS,
  validateArticle,
} from "../_shared/structure.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-subscription-tier, x-user-gemini-key",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Trial-phase cap: anon users may process a full edition, bounded by the
// 2/hour/IP rate limit below. Tighten with real auth tiers later.
const MAX_PAGES = 24;
const SARVAM_BASE = "https://api.sarvam.ai";

function jwtRole(req: Request): string {
  try {
    const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    return payload.role ?? "";
  } catch {
    return "";
  }
}

// ── Sarvam OCR for one page-PDF (doc-digitization job flow) ──────────────────

async function sarvamPost(path: string, key: string, body: unknown): Promise<Record<string, unknown>> {
  const r = await fetch(`${SARVAM_BASE}${path}`, {
    method: "POST",
    headers: { "api-subscription-key": key, "Content-Type": "application/json" },
    body: JSON.stringify(body ?? {}),
    signal: AbortSignal.timeout(30_000),
  });
  if (!r.ok) throw new Error(`${path} -> HTTP ${r.status}: ${(await r.text()).slice(0, 120)}`);
  return await r.json() as Record<string, unknown>;
}

async function ocrPageToHtml(pageBytes: Uint8Array, sarvamKey: string): Promise<string> {
  const job = await sarvamPost("/doc-digitization/job/v1", sarvamKey, {
    job_parameters: { language: "te-IN", output_format: "html" },
  }) as { job_id: string };

  const up = await sarvamPost("/doc-digitization/job/v1/upload-files", sarvamKey, {
    job_id: job.job_id,
    files: ["page.pdf"],
  }) as { upload_urls: Record<string, { file_url: string; file_metadata?: Record<string, string> }> };
  const info = Object.values(up.upload_urls)[0];
  const headers: Record<string, string> = { "x-ms-blob-type": "BlockBlob" };
  for (const [k, v] of Object.entries(info.file_metadata ?? {})) {
    if (typeof v === "string") headers[k] = v;
  }
  const put = await fetch(info.file_url, { method: "PUT", body: pageBytes as BodyInit, headers });
  if (!put.ok) throw new Error(`OCR upload PUT -> ${put.status}`);

  await sarvamPost(`/doc-digitization/job/v1/${job.job_id}/start`, sarvamKey, {});
  let state = "";
  // 90s was too tight: pages 11 and 12 of a real edition both died on
  // "OCR job timed out" while Sarvam was merely slow, and a failed page is
  // dropped from the edition permanently. 150s costs nothing when OCR is fast.
  for (let i = 0; i < 30; i++) {
    await new Promise((r) => setTimeout(r, 5000));
    const st = await fetch(`${SARVAM_BASE}/doc-digitization/job/v1/${job.job_id}/status`, {
      headers: { "api-subscription-key": sarvamKey },
    });
    state = ((await st.json()) as { job_state?: string }).job_state ?? "";
    if (state === "Completed") break;
    if (state === "Failed" || state === "Cancelled") throw new Error(`OCR job ${state}`);
  }
  if (state !== "Completed") throw new Error("OCR job timed out");

  const dl = await sarvamPost(`/doc-digitization/job/v1/${job.job_id}/download-files`, sarvamKey, {}) as {
    download_urls: Record<string, { file_url: string } | string>;
  };
  for (const v of Object.values(dl.download_urls)) {
    const url = typeof v === "string" ? v : v.file_url;
    if (typeof url !== "string" || !url.startsWith("http")) continue;
    const resp = await fetch(url);
    if (!resp.ok) continue;
    const buf = new Uint8Array(await resp.arrayBuffer());
    if (buf[0] === 0x50 && buf[1] === 0x4b) {  // zip
      const { ZipReader, Uint8ArrayReader, TextWriter } =
        await import("https://deno.land/x/zipjs@v2.7.45/index.js");
      const zr = new ZipReader(new Uint8ArrayReader(buf));
      for (const entry of await zr.getEntries()) {
        if (!entry.directory && /\.html?$/i.test(entry.filename)) {
          const html = await entry.getData?.(new TextWriter()) as string;
          await zr.close();
          return html;
        }
      }
      await zr.close();
    } else {
      const text = new TextDecoder().decode(buf);
      if (text.includes("<")) return text;
    }
  }
  throw new Error("no HTML in OCR result");
}

// "Eenadu_TELANGANA_20260512.pdf" → "2026-05-12"
// Also the separated forms real uploads actually use: "NT-2026-07-26.pdf" and
// "NT-24-07-2026.pdf". The digits-only pattern matched neither, so both fell
// through to model date detection unnecessarily.
function parseDateFromFilename(name: string): string {
  const ok = (y: string, mo: string, d: string) =>
    +mo >= 1 && +mo <= 12 && +d >= 1 && +d <= 31
      ? `${y}-${mo.padStart(2, "0")}-${d.padStart(2, "0")}`
      : "";
  // YYYY?MM?DD
  let m = name.match(/(20\d{2})[-_.]?(\d{2})[-_.]?(\d{2})/);
  if (m) {
    const r = ok(m[1], m[2], m[3]);
    if (r) return r;
  }
  // DD?MM?YYYY
  m = name.match(/(\d{1,2})[-_.](\d{1,2})[-_.](20\d{2})/);
  if (m) {
    const r = ok(m[3], m[2], m[1]);
    if (r) return r;
  }
  return "";
}

// Indian newspapers print by IST calendar day, but the edge runtime's wall
// clock is UTC — a plain toISOString() split would misdate anything uploaded
// 00:00-05:30 IST as the previous day. IST is a fixed UTC+5:30, no DST.
function todayIST(): string {
  return new Date(Date.now() + 5.5 * 3600_000).toISOString().split("T")[0];
}

function bytesToBase64(bytes: Uint8Array): string {
  const CHUNK = 8192;
  let binary = "";
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, Math.min(i + CHUNK, bytes.length)));
  }
  return btoa(binary);
}

// The date actually printed on the page (masthead/dateline) is the ground
// truth for "which edition is this" — most uploads (camera photos) have no
// dated filename, and would otherwise all collide on today's date. Cheap
// flash-lite vision call; failures are non-fatal (caller falls back to the
// filename, then today).
async function detectPrintedDate(pageBytes: Uint8Array, geminiKey: string): Promise<string> {
  try {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${geminiKey}`;
    // Deliberately the FLAT page, not the banded one. Banding helps every other
    // vision call, but here it destabilised the read: a page printed 26.7.2026
    // came back as 2023-07-26, which forked a duplicate edition under the wrong
    // date. The flat page had returned the correct date on every prior run, and
    // this call only needs one number.
    const prompt = 'If a publication/issue date is printed on this newspaper page ' +
      '(masthead or dateline), return it as YYYY-MM-DD. Otherwise return "". ' +
      'Return ONLY JSON: {"publicationDate":""}';
    const resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{
          role: "user",
          parts: [
            { inline_data: { mime_type: "application/pdf", data: bytesToBase64(pageBytes) } },
            { text: prompt },
          ],
        }],
        generationConfig: {
          maxOutputTokens: 256,
          responseMimeType: "application/json",
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
      signal: AbortSignal.timeout(20_000),
    });
    if (!resp.ok) {
      await resp.body?.cancel();
      return "";
    }
    const data = await resp.json() as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };
    const text = (data.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? "").join("");
    const m = text.match(/"publicationDate"\s*:\s*"(\d{4}-\d{2}-\d{2})"/);
    return m ? m[1] : "";
  } catch (e) {
    console.warn("[edition] printed-date detection failed:", (e as Error).message);
    return "";
  }
}

function estimateDurationSeconds(text: string): number {
  return Math.max(15, Math.round((text.length / 700) * 60));
}

// Wrap a JPEG/PNG into a single-page PDF (page sized to the image). If the bytes
// are already a PDF (or an unrecognized type), return them unchanged.
async function normalizeToPdf(bytes: Uint8Array): Promise<Uint8Array> {
  const isJpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPng = bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47;
  if (!isJpeg && !isPng) return bytes; // already PDF (or let load() error clearly)

  const doc = await PDFDocument.create();
  const img = isJpeg ? await doc.embedJpg(bytes) : await doc.embedPng(bytes);
  const page = doc.addPage([img.width, img.height]);
  page.drawImage(img, { x: 0, y: 0, width: img.width, height: img.height });
  return await doc.save();
}

// ── Page continuation ─────────────────────────────────────────────────────────

// deno-lint-ignore no-explicit-any
async function processPage(
  supabase: any, jobId: string, page: number, geminiKey: string,
): Promise<void> {
  const SARVAM = Deno.env.get("SARVAM_API_KEY")!;
  const GEMINI = geminiKey;

  const { data: job } = await supabase
    .from("processing_jobs").select("*").eq("id", jobId).single();
  if (!job || job.status === "failed") return;

  const sourcePath = job.source_path ?? `editions/${jobId}.pdf`;
  try {
    // load source PDF from storage and cut out this page
    const { data: blob, error: dlErr } = await supabase.storage
      .from("uploads").download(sourcePath);
    if (dlErr) throw new Error(`pdf download: ${dlErr.message}`);
    const srcBytes = await normalizeToPdf(new Uint8Array(await blob.arrayBuffer()));
    const src = await PDFDocument.load(srcBytes);
    const single = await PDFDocument.create();
    const [pg] = await single.copyPages(src, [page - 1]);
    single.addPage(pg);
    const pageBytes = await single.save();

    // One retry. A page that fails here is recorded in failed_pages and never
    // revisited, so a single transient Sarvam hiccup silently costs the edition
    // an entire page — a worse outcome than any extraction error we chase.
    let html: string;
    try {
      html = await ocrPageToHtml(new Uint8Array(pageBytes), SARVAM);
    } catch (e) {
      console.warn(`[edition] page ${page} OCR failed (${(e as Error).message}); retrying once`);
      html = await ocrPageToHtml(new Uint8Array(pageBytes), SARVAM);
    }
    const result = await extractArticlesStructured(
      html, new Uint8Array(pageBytes), "application/pdf", GEMINI);

    const rows = result.articles.map((a, i) => ({
      newspaper_id: job.newspaper_id,
      title: a.title,
      content_preview: a.content.replace(/\n/g, " ").slice(0, 200),
      full_content: a.content,
      section: a.category || "News",
      // Prefer the printed page number (cover/main pages shift the PDF index).
      page_number: result.printedPage ?? page,
      processing_status: needsReview(a.review) ? "review" : "ready",
      quality_score: needsReview(a.review) ? 0.7 : 0.95,
      position_json: {
        article_index: i + 1,
        page: result.printedPage ?? page,
        pdf_page: page,
        subheadings: a.subheadings,
        captions: a.captions,
        review_flags: a.review.length ? a.review : undefined,
        estimated_duration_seconds: estimateDurationSeconds(a.content),
        extraction_engine: "structured-v1",
      },
    }));
    const { error: insErr } = await supabase.from("articles").insert(rows);
    if (insErr) throw new Error(`articles insert: ${insErr.message}`);

    const totalArticles = (job.article_count ?? 0) + rows.length;
    const isLastPage = page >= job.total_pages;
    await supabase.from("processing_jobs").update({
      done_pages: page,
      article_count: totalArticles,
      // Every page can individually "succeed" (OCR + insert with 0 rows, or a
      // structuring fallback that still returns valid-but-empty JSON) while the
      // edition as a whole produced nothing usable — status must reflect the
      // final article count, not just "did the last page throw."
      status: isLastPage ? (totalArticles > 0 ? "completed" : "failed") : "processing",
      ...(isLastPage && totalArticles === 0
        ? { error: "OCR completed on every page but no articles were extracted." }
        : {}),
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);
    console.log(`[edition] job ${jobId} page ${page}/${job.total_pages}: ${rows.length} articles`);
  } catch (e) {
    const msg = (e as Error).message;
    console.warn(`[edition] page ${page} failed: ${msg}`);
    const totalArticles = job.article_count ?? 0;
    const isLastPage = page >= job.total_pages;
    await supabase.from("processing_jobs").update({
      done_pages: page,
      failed_pages: [...(job.failed_pages ?? []), { page, error: msg.slice(0, 200) }],
      status: isLastPage ? (totalArticles > 0 ? "completed" : "failed") : "processing",
      ...(isLastPage && totalArticles === 0
        ? { error: `All pages failed; last error: ${msg.slice(0, 200)}` }
        : {}),
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);
  }

  // chain next page, or finish: delete the source file (articles + audio are
  // the product; the source PDF is no longer needed — saves storage).
  if (page < job.total_pages) {
    fireContinuation(jobId, page + 1, geminiKey);
  } else {
    // All pages done — stitch cross-page article continuations, re-judge which
    // articles are still worth withholding now that bodies are final, then
    // clean up.
    await finalizeContinuations(supabase, job.newspaper_id, geminiKey);
    await recomputeReviewStatus(supabase, job.newspaper_id);
    await supabase.storage.from("uploads").remove([sourcePath])
      .then(() => {}, () => {});
    console.log(`[edition] job ${jobId} completed; source ${sourcePath} deleted`);
  }
}

// ── Cross-page continuation stitching ────────────────────────────────────────
// Telugu papers split long articles across pages: the body ends with a marker
// like "(మిగతా 3వ పేజీలో)" / "మిగతా 3లో" / "సశేషం 5వ పేజీలో", and the rest sits
// on page N under a "(... తరువాయి)" continuation header. This runs once, after
// every page is extracted (the only point all pages coexist). Conservative:
// only merges on a strong match (continuation header OR matching headline) to
// avoid fusing unrelated articles; otherwise it just strips the dangling marker
// so it isn't read aloud.

// "continued TO page N" — captures the page number. Two forms in real
// editions: the spelled-out "మిగతా/సశేషం/తరువాయి ... N వ పేజీలో", and a bare
// ">N" or ">Nవ పేజీలో" shorthand (a small arrow glyph OCR renders as ">")
// that carries no continuation keyword at all — e.g. "సంజీవ్ కుమార్ > 7" or
// "'48 గంటల్లో > 2వ పేజీలో". Missing the second form meant every article
// using it never even reached the merge logic below, since `body.match
// (CONT_TO)` returned null and skipped the whole per-article loop.
const CONT_TO =
  /(?:(?:మిగతా|సశేషం|తరువాయి)\s*\(?\s*(?<page1>\d{1,2})\s*(?:వ\s*)?(?:పేజీలో|పేజీ|లో)[^)]*\)?)|(?:>\s*(?<page2>\d{1,2})\s*(?:వ\s*పేజీలో)?)/;
// "continued FROM" header at the start of the destination article.
const CONT_FROM = /(?:\d{1,2}\s*(?:వ\s*)?పేజీ|మొదటి\s*పేజీ)\s*తరువాయి/;

// Continuation-page headlines are often shortened from the original (trimmed
// to save space) — sometimes a prefix, sometimes a fragment lifted from
// elsewhere in the original headline, not always starting at character 0.
// Comparing a fixed 10-char slice for exact equality missed most real
// cases. Check whether the shorter (normalized) title appears ANYWHERE in
// the longer one, with a length floor so short titles can't false-positive
// on a shared common word.
// Collapse runs of spaces/tabs WITHOUT touching newlines, so paragraph breaks
// survive. Body text is stored with "\n\n" between paragraphs and the app reads
// it back that way; a plain /\s{2,}/ collapse silently destroys that.
function squashSpaces(s: string): string {
  return s
    .replace(/[^\S\n]{2,}/g, " ")
    .replace(/[^\S\n]*\n[^\S\n]*/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

// Longest common subsequence length, for comparing two OCR renderings of the
// same printed headline. Titles are short, so the O(n*m) table is cheap.
function lcsLen(a: string, b: string): number {
  let prev = new Array(b.length + 1).fill(0);
  for (let i = 1; i <= a.length; i++) {
    const cur = new Array(b.length + 1).fill(0);
    for (let j = 1; j <= b.length; j++) {
      cur[j] = a[i - 1] === b[j - 1]
        ? prev[j - 1] + 1
        : Math.max(prev[j], cur[j - 1]);
    }
    prev = cur;
  }
  return prev[b.length];
}

function titleOverlapMatch(t1: string, t2: string): boolean {
  const n1 = (t1 ?? "").trim().replace(/\s+/g, " ");
  const n2 = (t2 ?? "").trim().replace(/\s+/g, " ");
  if (!n1 || !n2) return false;
  const [shorter, longer] = n1.length <= n2.length ? [n1, n2] : [n2, n1];
  if (shorter.length < 10) return false;
  if (longer.includes(shorter)) return true;
  // Exact containment also breaks on OCR variance. This paper's second front-page
  // lead was read as "ఒడిసిపడ్డరా.. ఇడిసిపెద్దరా?" on page 1 and
  // "ఒడిసిపడ్డా.. ఇడిసిపెడ్డారా?" on its page-8 continuation — the same printed
  // headline a few characters apart — so `includes` failed, the score stayed at
  // 0, and the two halves were never joined. Fall back to character similarity.
  return lcsLen(shorter, longer) / shorter.length >= 0.8;
}

// Fallback for when neither the CONT_FROM header nor titleOverlapMatch
// confidently resolves a match — the continuation headline may be a genuine
// paraphrase (same story, different wording) rather than a truncation,
// which no string comparison can catch. Only called for articles that
// already have a real "continued on page N" marker and at least one
// same-page candidate the deterministic checks left unresolved, so this
// stays rare and targeted rather than a call per article.
async function semanticContinuationMatch(
  sourceTitle: string,
  sourceBody: string,
  candidates: Array<{ title: string; body: string }>,
  geminiKey: string,
): Promise<number | null> {
  if (!geminiKey || !candidates.length) return null;
  const prompt =
    `A Telugu newspaper article says it continues on another page. Below is ` +
    `that article's headline + opening text, and a numbered list of candidate ` +
    `articles found on the target page. Decide which candidate (if any) is ` +
    `genuinely the CONTINUATION of the same story — same event, same ` +
    `people/place, picking up where the first part left off. Headlines are ` +
    `often reworded or shortened on the continuation page, so judge by ` +
    `CONTENT, not matching words.\n\n` +
    `Return ONLY JSON: {"match": <candidate index, or -1 if none confidently match>}\n\n` +
    `SOURCE:\nheadline: "${sourceTitle.slice(0, 80)}"\nopening: "${sourceBody.slice(0, 150)}"\n\n` +
    `CANDIDATES:\n${
      candidates
        .map((c, i) =>
          `[${i}] headline: "${c.title.slice(0, 80)}"\n    opening: "${c.body.slice(0, 150)}"`
        )
        .join("\n")
    }`;
  const { status, text } = await callGeminiJson("gemini-2.5-flash-lite", [{ text: prompt }], geminiKey);
  if (status !== 200) return null;
  const data = JSON.parse((text.match(/\{[\s\S]*\}/) ?? ["{}"])[0]) as { match?: number };
  return typeof data.match === "number" && data.match >= 0 && data.match < candidates.length
    ? data.match
    : null;
}

// City+date dateline opening a brief: "న్యూఢిల్లీ, జూలై 25:",
// "హైదరాబాద్, జూలై 25(నమస్తే తెలంగాణ):". stripLeadingDateline in structure.ts
// only knows publication bylines (ఈనాడు / న్యూస్‌టుడే / సాక్షి), so these
// survived into the teaser probe below — and since every Delhi-datelined story
// on a page shares this prefix, it alone was enough to "match" two unrelated
// articles.
const CITY_DATE_LEAD =
  /^[\s•]*[ఀ-౿]{2,20}\s*,\s*[ఀ-౿]{2,12}\s*\d{1,2}\s*(?:\([^)]{0,40}\))?\s*:\s*/;

// Share of the teaser's OWN text that must appear verbatim inside the full
// story before the two are treated as the same item.
const TEASER_CONTAINMENT = 0.6;

// The previous test was: does ONE 18-codepoint window from the short article
// appear anywhere in the long one. In Telugu 18 codepoints is 2-4 words, and
// the window at offset 0 is the dateline — so an NTPC funding brief matched a
// story about a minister resigning, purely because both were datelined
// "న్యూఢిల్లీ, జూలై 25", and the brief was then deleted with its headline glued
// onto the unrelated article. This instead measures how much of the teaser is
// actually reproduced in the candidate: a genuine front-page blurb is largely
// echoed by the full story, a coincidental dateline match is not.
function teaserContainment(short: string, long: string): number {
  const s = short.replace(CITY_DATE_LEAD, "").replace(/\s+/g, " ").trim();
  const l = (long ?? "").replace(/\s+/g, " ");
  const WIN = 40;
  if (s.length < WIN * 2 || !l) return 0;
  let total = 0;
  let hit = 0;
  for (let i = 0; i + WIN <= s.length; i += WIN) {
    total++;
    if (l.includes(s.slice(i, i + WIN))) hit++;
  }
  return total ? hit / total : 0;
}

// deno-lint-ignore no-explicit-any
async function finalizeContinuations(
  supabase: any, newspaperId: string, geminiKey: string,
): Promise<void> {
  if (!newspaperId) return;
  const { data: arts } = await supabase.from("articles")
    .select("id,title,full_content,content_preview,page_number,position_json")
    .eq("newspaper_id", newspaperId)
    .order("page_number");
  if (!arts || arts.length < 2) return;

  // ── Front-page teaser → stitch its headline onto the full story ───────────
  // Front pages carry short promo blurbs ("…full story on page 8") whose text is
  // echoed by the full article elsewhere. Rather than drop them, prepend the
  // teaser's headline (the front-page kicker) to the full article's headline so
  // the listener knows this was the front-page lead — then remove the blurb.
  type Art = { id: string; title: string; full_content: string; position_json?: Record<string, unknown> };
  const longs = (arts as Art[]).filter((x) => (x.full_content?.length ?? 0) > 500);
  for (const a of arts as Art[]) {
    const body = a.full_content ?? "";
    // Was capped at 260 — too narrow. Real front-page highlight/quote boxes
    // measured in production run 400-500+ chars (a multi-sentence pull-quote,
    // not just a one-line kicker), so they never even reached the substring
    // probe below. 600 covers those while still excluding genuinely
    // independent full-length articles.
    if (body.length >= 600 || body.length < 30) continue;
    let match: Art | undefined;
    let bestRatio = 0;
    for (const L of longs) {
      if (L.id === a.id) continue;
      const r = teaserContainment(body, L.full_content ?? "");
      if (r > bestRatio) { bestRatio = r; match = L; }
    }
    if (!match || bestRatio < TEASER_CONTAINMENT) continue;
    const kicker = (a.title ?? "").trim();
    // Only stitch a clean, short kicker; otherwise just drop the blurb.
    if (kicker && kicker.length <= 36 && !(match.title ?? "").includes(kicker)) {
      await supabase.from("articles")
        .update({ title: `${kicker} — ${match.title}` }).eq("id", match.id);
      console.log(`[edition] stitched front-page kicker "${kicker}" → full story`);
    }
    // Marked, not deleted. A hard DELETE here made a bad match unrecoverable
    // AND invisible — the only trace was a shrinking article count. "absorbed"
    // is filtered out of the app the same way (it fetches processing_status
    // =ready), but the row survives for audit and can be restored.
    await supabase.from("articles").update({
      processing_status: "absorbed",
      position_json: {
        ...(a.position_json ?? {}),
        absorbed_into: match.id,
        absorbed_ratio: Number(bestRatio.toFixed(2)),
      },
    }).eq("id", a.id);
    console.log(`[edition] absorbed teaser "${(a.title ?? "").slice(0, 24)}" → ${match.id} (${bestRatio.toFixed(2)})`);
  }

  // A continuation belongs to exactly ONE story, and several articles can point
  // at the same target page — a lead's "➤7వ పేజీలో" and a teaser box reading
  // "…గెలుపు > 7" both resolve to page 7. Claiming it inside the loop meant
  // whichever article came first in `arts` won, regardless of how well it
  // matched: on the front page the 120-char teaser took the continuation and
  // the real lead story got none. So resolve in two passes — score every claim
  // first, then award each continuation to its strongest claimant.
  //
  // Scores are coarse (0 / 2 / 4), so ties are common; the longer source wins
  // them, since a full lead story is a likelier parent than a promo box.
  type Claim = {
    // deno-lint-ignore no-explicit-any
    a: any; best: any | null; score: number; head: string; body: string; targetPage: number;
  };
  const claims: Claim[] = [];
  for (const a of arts) {
    const body: string = a.full_content ?? "";
    const m = body.match(CONT_TO);
    if (!m) continue;
    const targetPage = parseInt(m.groups?.page1 ?? m.groups?.page2 ?? "", 10);
    if (Number.isNaN(targetPage)) continue;

    const cands = arts.filter((x: typeof a) =>
      x.page_number === targetPage && x.id !== a.id && x.full_content);
    let best: typeof a | null = null;
    let bestScore = 0;
    for (const c of cands) {
      const head = (c.full_content as string).slice(0, 90);
      let score = 0;
      if (CONT_FROM.test(head)) score += 2;
      if (titleOverlapMatch(a.title as string, c.title as string)) score += 2;
      if (score > bestScore) { bestScore = score; best = c; }
    }

    // Deterministic checks found nothing confident, but there's a real
    // "continued on page N" marker and at least one same-page candidate —
    // the continuation headline may be a paraphrase rather than a
    // truncation/overlap. Ask Gemini to judge by content instead of text.
    if (bestScore < 2 && cands.length) {
      const idx = await semanticContinuationMatch(
        a.title as string,
        body,
        cands.map((c: typeof a) => ({
          title: (c.title as string) ?? "",
          body: (c.full_content as string) ?? "",
        })),
        geminiKey,
      ).catch(() => null);
      if (idx !== null) {
        best = cands[idx];
        bestScore = 2;
        console.log(`[edition] semantic continuation match p→${targetPage}: "${(a.title as string).slice(0, 24)}"`);
      }
    }

    // Strip the dangling "continued to" marker from this article regardless.
    // squashSpaces, not /\s{2,}/ — \s matches newlines, so the old collapse
    // turned every paragraph break into a space and left any article that got
    // a continuation merged as one unbroken 6000-character blob.
    const head = squashSpaces(body.replace(CONT_TO, " "));
    claims.push({ a, best, score: bestScore, head, body, targetPage });
  }

  claims.sort((x, y) =>
    y.score - x.score || (y.body?.length ?? 0) - (x.body?.length ?? 0));

  const consumed = new Set<string>();
  for (const c of claims) {
    // This source was itself absorbed as someone else's continuation.
    if (consumed.has(c.a.id)) continue;
    if (c.best && c.score >= 2 && !consumed.has(c.best.id)) {
      const contBody = squashSpaces(
        (c.best.full_content as string)
          .replace(CONT_FROM, " ")
          .replace(/^[\s\S]{0,40}?తరువాయి[^)]*\)?/, " "), // drop leading header line
      );
      // Paragraph break at the seam: the continuation resumes on another page,
      // so it is never a mid-paragraph continuation of the last line.
      const merged = `${c.head}\n\n${contBody}`.trim();
      await supabase.from("articles")
        .update({ full_content: merged, content_preview: merged.slice(0, 200) })
        .eq("id", c.a.id);
      consumed.add(c.best.id);
      c.a.full_content = merged;
      await supabase.from("articles").delete().eq("id", c.best.id);
      console.log(`[edition] merged continuation p→${c.targetPage}: "${(c.a.title as string).slice(0, 24)}" (score ${c.score})`);
    } else if (c.head !== c.body) {
      // Lost the claim, or no confident match — at least don't read the
      // dangling "continued on page N" marker aloud.
      await supabase.from("articles")
        .update({ full_content: c.head, content_preview: c.head.slice(0, 200) })
        .eq("id", c.a.id);
    }
  }
}

// Review status is decided at insert time, but finalizeContinuations rewrites
// bodies afterwards — merging in the continuation half and stripping the
// "continued on page N" marker. An article held back as `ends_mid_sentence`
// purely because of that marker is complete once merged, yet nothing ever
// recomputed its status, so it stayed invisible (the app fetches
// processing_status=ready only). Front pages carry the most continued stories,
// which is how page 1 of an edition could end up with every article withheld.
async function recomputeReviewStatus(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  newspaperId: string,
): Promise<void> {
  if (!newspaperId) return;
  const { data: arts } = await supabase.from("articles")
    .select("id,title,full_content,processing_status,position_json")
    .eq("newspaper_id", newspaperId)
    // "absorbed" is a terminal decision from the teaser pass — recomputing it
    // from review flags would hand the blurb a ready/review status again and
    // put the duplicate straight back in front of the reader.
    .neq("processing_status", "absorbed");
  if (!arts) return;

  let promoted = 0;
  for (const a of arts) {
    const prior: string[] = a.position_json?.review_flags ?? [];
    // Keep the process-level flags as recorded; re-derive the text-level ones
    // from the body as it stands now, post-stitching.
    const kept = prior.filter(
      (f) => !TEXT_DERIVED_FLAGS.some((t) => f.startsWith(t)));
    const flags = [
      ...kept,
      ...validateArticle({ title: a.title ?? "", content: a.full_content ?? "" }),
    ];
    const hold = needsReview(flags);
    if (!hold && a.processing_status === "review") promoted++;
    await supabase.from("articles").update({
      processing_status: hold ? "review" : "ready",
      quality_score: hold ? 0.7 : 0.95,
      position_json: {
        ...(a.position_json ?? {}),
        review_flags: flags.length ? flags : undefined,
      },
    }).eq("id", a.id);
  }
  console.log(`[edition] review recompute: ${promoted} of ${arts.length} promoted to ready`);
}

function fireContinuation(jobId: string, page: number, geminiKey: string): void {
  const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/documents-process-edition`;
  // Anon JWT satisfies the gateway; the service key travels in x-internal-token
  // and is string-compared by our gate (it may be an opaque sb_secret_ key,
  // which is not a decodable JWT — see jwtRole).
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const internal = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const p = fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${anon}`,
      "apikey": anon,
      "x-internal-token": internal,
    },
    // The user's Gemini key rides along the internal continuation chain only —
    // it's never written to a table (processing_jobs has no such column).
    body: JSON.stringify({ job_id: jobId, page, geminiKey }),
  }).then(async (r) => {
    if (!r.ok) console.warn(`[edition] continuation page ${page} -> HTTP ${r.status}`);
    await r.body?.cancel();
  }).catch((e) => console.warn("[edition] continuation fire failed:", e.message));
  // deno-lint-ignore no-explicit-any
  (globalThis as any).EdgeRuntime?.waitUntil?.(p);
}

// ── Main ──────────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SERVICE_KEY || !Deno.env.get("SARVAM_API_KEY") || !Deno.env.get("GEMINI_API_KEY")) {
    return json({ error: "config_missing" }, 500);
  }
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

  const contentType = req.headers.get("content-type") ?? "";

  if (contentType.includes("application/json")) {
    const body = await req.json().catch(() => ({})) as {
      job_id?: string; page?: number; geminiKey?: string;
      storagePath?: string; filename?: string;
    };

    // ── internal continuation (service-key holders only) ──────────────────
    if (body.job_id && body.page) {
      const internal = req.headers.get("x-internal-token") ?? "";
      if (internal !== SERVICE_KEY && jwtRole(req) !== "service_role") {
        return json({ error: "forbidden" }, 403);
      }
      await processPage(supabase, body.job_id, body.page, body.geminiKey ?? "");
      return json({ ok: true, job_id: body.job_id, page: body.page });
    }

    // ── public: start from a pre-uploaded storage path (durable path) ─────
    if (body.storagePath) {
      return await runStart(supabase, req, SUPABASE_URL!,
        { storagePath: body.storagePath, filename: body.filename || "edition.pdf" });
    }
    return json({ error: "bad_request" }, 400);
  }

  // ── public: start from a multipart upload (legacy / small files) ────────
  return await runStart(supabase, req, SUPABASE_URL!, { multipart: true });
});

// Shared edition starter. Source is either a multipart file in the request, or
// a path the client already uploaded straight to storage (the durable path —
// the heavy byte transfer never touches this function).
async function runStart(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  req: Request,
  SUPABASE_URL: string,
  source: { multipart?: boolean; storagePath?: string; filename?: string },
): Promise<Response> {
  try {
    // Shared GatiVāni key — OCR/structuring runs on our own Gemini quota, not
    // BYOK. Presence is already guaranteed by the config_missing check at the
    // top of the handler; the rate limit below is what actually bounds cost
    // now that this isn't gated behind each caller bringing their own key.
    const userGeminiKey = Deno.env.get("GEMINI_API_KEY")!;

    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
    const oneHourAgo = new Date(Date.now() - 3600_000).toISOString();
    const { count } = await supabase
      .from("request_log").select("*", { count: "exact", head: true })
      .eq("ip", ip).eq("endpoint", "documents-process-edition")
      .gte("created_at", oneHourAgo);
    if ((count ?? 0) >= 20) {
      return json({ error: "rate_limited", message: "Edition limit: 20 per hour." }, 429);
    }
    await supabase.from("request_log").insert({ ip, endpoint: "documents-process-edition" });

    let originalName: string;
    let sourcePath: string;       // where the source lives in the uploads bucket
    let bytes: Uint8Array;        // normalized PDF bytes, for page counting

    if (source.multipart) {
      const form = await req.formData();
      const file = form.get("document");
      if (!(file instanceof File)) return json({ error: "missing_file" }, 400);
      if (file.size > 60 * 1024 * 1024) return json({ error: "file_too_large", message: "Max 60 MB." }, 413);
      originalName = file.name || "edition.pdf";
      const safe = originalName.replace(/[^a-zA-Z0-9._-]/g, "_");
      sourcePath = `editions/${Date.now()}_${safe}`;
      bytes = await normalizeToPdf(new Uint8Array(await file.arrayBuffer()));
      const { error: upErr } = await supabase.storage.from("uploads")
        .upload(sourcePath, bytes, { contentType: "application/pdf", upsert: true });
      if (upErr) throw new Error(`pdf store: ${upErr.message}`);
    } else {
      originalName = source.filename!;
      sourcePath = source.storagePath!;
      const { data: blob, error: dlErr } = await supabase.storage
        .from("uploads").download(sourcePath);
      if (dlErr) throw new Error(`source download: ${dlErr.message}`);
      bytes = await normalizeToPdf(new Uint8Array(await blob.arrayBuffer()));
    }

    const pdf = await PDFDocument.load(bytes);
    const totalPages = Math.min(pdf.getPageCount(), MAX_PAGES);
    if (totalPages === 0) return json({ error: "empty_pdf" }, 400);

    // Ground the edition's date in what's actually printed on page 1, so a
    // fresh scan of yesterday's paper doesn't get mislabeled/merged as today.
    // A date in the filename is deterministic; printed-date detection is a model
    // read that can misfire, and when it does it forks a duplicate edition under
    // the wrong date rather than replacing the right one. So trust the filename
    // when it carries a date, and keep detection for the case it was added for:
    // camera photos whose names carry nothing.
    let pubDate = parseDateFromFilename(originalName);
    if (!pubDate) {
      const single = await PDFDocument.create();
      const [pg] = await single.copyPages(pdf, [0]);
      single.addPage(pg);
      pubDate = await detectPrintedDate(await single.save(), userGeminiKey);
    }
    pubDate = pubDate || todayIST();
    const title = originalName.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim();

    let newspaperId: string;
    const { data: existing } = await supabase
      .from("newspapers").select("id")
      .eq("title", title).eq("publication_date", pubDate).limit(1).maybeSingle();
    if (existing?.id) {
      newspaperId = existing.id;
      // Reprocessing the same edition: clear its old articles so we replace
      // rather than duplicate.
      await supabase.from("articles").delete().eq("newspaper_id", newspaperId);
    } else {
      const { data: created, error: nErr } = await supabase
        .from("newspapers")
        .insert({ title, publication_date: pubDate, language: "te" })
        .select("id").single();
      if (nErr) throw new Error(`newspaper insert: ${nErr.message}`);
      newspaperId = created.id;
    }

    const { data: jobRow, error: jErr } = await supabase
      .from("processing_jobs")
      .insert({
        filename: originalName, status: "processing",
        total_pages: totalPages, newspaper_id: newspaperId, source_path: sourcePath,
      })
      .select("id").single();
    if (jErr) throw new Error(`job insert: ${jErr.message}`);
    const jobId = jobRow.id as string;

    fireContinuation(jobId, 1, userGeminiKey);
    return json({ ok: true, jobId, newspaperId, totalPages, pubDate });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-process-edition]", err);
    return json({ error: "edition_failed", message }, 500);
  }
}
