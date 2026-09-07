// Edition ingest helpers, shared by the pipeline functions.
//
// Extracted verbatim from documents-process-edition so pipeline-page and
// pipeline-finalize use exactly the same OCR, PDF and continuation logic the
// old chain did — this move is a refactor, not a rewrite. The behaviour tuned
// against real Telugu editions (Sarvam's job flow, the continuation markers,
// the conservative merge rules) is carried over unchanged.

import { PDFDocument } from "npm:pdf-lib@1.17.1";
import { generate, type UsageCtx } from "./gemini.ts";

export const SARVAM_BASE = "https://api.sarvam.ai";


// "continued TO page N" — captures the page number. `>` alongside the three
// words: a real front page ("...దానికి >7వ పేజీలో") printed the jump as a bare
// arrow glyph with no qualifying word at all, which this regex missed
// entirely on the first edition run — those articles never even reached the
// candidate-matching below, let alone the semantic fallback.
const CONT_TO = /(?:మిగతా|సశేషం|తరువాయి|>)\s*\(?\s*(\d{1,2})\s*(?:వ\s*)?(?:పేజీలో|పేజీ|లో)[^)]*\)?/;
// "continued FROM" header at the start of the destination article.
const CONT_FROM = /(?:\d{1,2}\s*(?:వ\s*)?పేజీ|మొదటి\s*పేజీ)\s*తరువాయి/;

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

export async function ocrPageToHtml(pageBytes: Uint8Array, sarvamKey: string): Promise<string> {
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
  // 24x5s = 120s. Bounded by pipeline-page's own wall-clock budget: the whole
  // invocation (this poll + the Gemini structure-extraction call that runs
  // after OCR completes) must fit inside Supabase's 150s Edge Function limit,
  // so this can't just be raised arbitrarily — 120s leaves ~30s for the rest.
  for (let i = 0; i < 24; i++) {
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

// "Eenadu_TELANGANA_20260512.pdf" → "2026-05-12"
export function parseDateFromFilename(name: string): string {
  const m = name.match(/(20\d{2})(\d{2})(\d{2})/);
  if (!m) return "";
  const [, y, mo, d] = m;
  if (+mo < 1 || +mo > 12 || +d < 1 || +d > 31) return "";
  return `${y}-${mo}-${d}`;
}

// Indian newspapers print by IST calendar day, but the edge runtime's wall
// clock is UTC — a plain toISOString() split would misdate anything uploaded
// 00:00-05:30 IST as the previous day. IST is a fixed UTC+5:30, no DST.

// Indian newspapers print by IST calendar day, but the edge runtime's wall
// clock is UTC — a plain toISOString() split would misdate anything uploaded
// 00:00-05:30 IST as the previous day. IST is a fixed UTC+5:30, no DST.
export function todayIST(): string {
  return new Date(Date.now() + 5.5 * 3600_000).toISOString().split("T")[0];
}

export function bytesToBase64(bytes: Uint8Array): string {
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

export function estimateDurationSeconds(text: string): number {
  return Math.max(15, Math.round((text.length / 700) * 60));
}

// Wrap a JPEG/PNG into a single-page PDF (page sized to the image). If the bytes
// are already a PDF (or an unrecognized type), return them unchanged.

// Wrap a JPEG/PNG into a single-page PDF (page sized to the image). If the bytes
// are already a PDF (or an unrecognized type), return them unchanged.
export async function normalizeToPdf(bytes: Uint8Array): Promise<Uint8Array> {
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

// Continuation-page headlines are often shortened from the original (trimmed
// to save space) — sometimes a prefix, sometimes a fragment lifted from
// elsewhere in the original headline, not always starting at character 0.
// Comparing a fixed 10-char slice for exact equality missed most real
// cases. Check whether the shorter (normalized) title appears ANYWHERE in
// the longer one, with a length floor so short titles can't false-positive
// on a shared common word.
function titleOverlapMatch(t1: string, t2: string): boolean {
  const n1 = (t1 ?? "").trim().replace(/\s+/g, " ");
  const n2 = (t2 ?? "").trim().replace(/\s+/g, " ");
  if (!n1 || !n2) return false;
  const [shorter, longer] = n1.length <= n2.length ? [n1, n2] : [n2, n1];
  if (shorter.length < 10) return false;
  return longer.includes(shorter);
}

// Fallback for when neither the CONT_FROM header nor titleOverlapMatch
// confidently resolves a match — the continuation headline may be a genuine
// paraphrase (same story, different wording) rather than a truncation,
// which no string comparison can catch. Only called for articles that
// already have a real "continued on page N" marker and at least one
// same-page candidate the deterministic checks left unresolved, so this
// stays rare and targeted rather than a call per article.

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
  ctx?: UsageCtx,
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
  const { status, text } = await generate({
    tier: "fast",
    parts: [{ text: prompt }],
    apiKey: geminiKey,
    ctx,
  });
  if (status !== 200) return null;
  const data = JSON.parse((text.match(/\{[\s\S]*\}/) ?? ["{}"])[0]) as { match?: number };
  return typeof data.match === "number" && data.match >= 0 && data.match < candidates.length
    ? data.match
    : null;
}

// deno-lint-ignore no-explicit-any

// deno-lint-ignore no-explicit-any
export async function finalizeContinuations(
  supabase: any, newspaperId: string, geminiKey: string, ctx?: UsageCtx,
): Promise<void> {
  if (!newspaperId) return;
  const { data: arts } = await supabase.from("articles")
    .select("id,title,full_content,content_preview,page_number,processing_status,position_json")
    .eq("newspaper_id", newspaperId)
    .order("page_number");
  if (!arts || arts.length < 2) return;

  // ── Front-page teaser → stitch its headline onto the full story ───────────
  // Front pages carry short promo blurbs ("…full story on page 8") whose text is
  // echoed by the full article elsewhere. Rather than drop them, prepend the
  // teaser's headline (the front-page kicker) to the full article's headline so
  // the listener knows this was the front-page lead — then remove the blurb.
  //
  // 260 was calibrated before any real edition ran through this. The first one
  // showed genuine front-page kickers running 600-3000+ chars (a paragraph,
  // not a one-line blurb) — 500 stays conservative against stitching two
  // merely-similar articles together, but reaches more of what's real.
  const longs = (arts as Array<{ id: string; title: string; full_content: string }>)
    .filter((x) => (x.full_content?.length ?? 0) > 500);
  for (const a of arts as Array<{ id: string; title: string; full_content: string }>) {
    const body = a.full_content ?? "";
    if (body.length >= 500 || body.length < 30) continue;
    let match: { id: string; title: string; full_content: string } | undefined;
    for (const off of [0, 12, 24, 40, 60]) {
      const probe = body.slice(off, off + 18).trim();
      if (probe.length < 12) continue;
      match = longs.find((L) => L.id !== a.id && L.full_content.includes(probe));
      if (match) break;
    }
    if (!match) continue;
    const kicker = (a.title ?? "").trim();
    // Only stitch a clean, short kicker; otherwise just drop the blurb.
    if (kicker && kicker.length <= 36 && !(match.title ?? "").includes(kicker)) {
      await supabase.from("articles")
        .update({ title: `${kicker} — ${match.title}` }).eq("id", match.id);
      console.log(`[edition] stitched front-page kicker "${kicker}" → full story`);
    }
    await supabase.from("articles").delete().eq("id", a.id);
  }

  for (const a of arts) {
    const body: string = a.full_content ?? "";
    const m = body.match(CONT_TO);
    if (!m) continue;
    const targetPage = parseInt(m[1], 10);

    // candidate continuations: articles on the target page
    const cands = arts.filter((x: typeof a) =>
      x.page_number === targetPage && x.id !== a.id && x.full_content);
    let best: typeof a | null = null;
    let bestScore = 0;
    for (const c of cands) {
      const head = (c.full_content as string).slice(0, 90);
      let score = 0;
      if (CONT_FROM.test(head)) score += 2;
      if (titleOverlapMatch(a.title as string, c.title as string)) {
        score += 2;
      }
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
        ctx,
      ).catch(() => null);
      if (idx !== null) {
        best = cands[idx];
        bestScore = 2;
        console.log(`[edition] semantic continuation match p→${targetPage}: "${(a.title as string).slice(0, 24)}"`);
      }
    }

    // Strip the dangling "continued to" marker from this article regardless.
    const head = body.replace(CONT_TO, " ").replace(/\s{2,}/g, " ").trim();

    if (best && bestScore >= 2) {
      const contBody = (best.full_content as string)
        .replace(CONT_FROM, " ")
        .replace(/^[\s\S]{0,40}?తరువాయి[^)]*\)?/, " ") // drop leading header line
        .replace(/\s{2,}/g, " ")
        .trim();
      const merged = `${head} ${contBody}`.trim();

      // A successful merge is the fix for exactly what put this article in
      // review in the first place — it was truncated (ends_mid_sentence),
      // and reordered/gap_suspected/low_coverage are page-extraction
      // artifacts a merge doesn't change either way. Drop those; anything
      // else (headline_missing, fused_articles, topic_mismatch, caption_leak,
      // vision_recovered) is an independent concern the merge didn't touch,
      // so it keeps gating. Without this a stitch "succeeds" in the logs and
      // the article stays invisible on its stale pre-merge flags regardless.
      const resolvedByMerge = new Set([
        "ends_mid_sentence", "reordered", "gap_suspected",
      ]);
      const priorFlags = ((a.position_json as { review_flags?: string[] } | null)
        ?.review_flags ?? []) as string[];
      const remainingFlags = priorFlags.filter((f) =>
        !resolvedByMerge.has(f) && !f.startsWith("low_coverage:"));

      await supabase.from("articles").update({
        full_content: merged,
        content_preview: merged.slice(0, 200),
        processing_status: remainingFlags.length ? "review" : "ready",
        quality_score: remainingFlags.length ? 0.7 : 0.95,
        position_json: {
          ...(a.position_json as Record<string, unknown> ?? {}),
          review_flags: remainingFlags.length ? remainingFlags : undefined,
        },
      }).eq("id", a.id);
      await supabase.from("articles").delete().eq("id", best.id);
      console.log(`[edition] merged continuation p→${targetPage}: "${(a.title as string).slice(0, 24)}"`);
    } else if (head !== body) {
      // No confident match — at least don't read the marker aloud.
      await supabase.from("articles")
        .update({ full_content: head, content_preview: head.slice(0, 200) })
        .eq("id", a.id);
    }
  }
}
