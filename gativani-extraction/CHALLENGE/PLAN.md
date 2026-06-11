# PLAN — Newspaper page → audio-ready articles (ground-up design)

*Author: Claude Fable 5. Phase 1 deliverable. A fresh session should be able to
execute the remaining phases from this file alone.*

---

## 1. The architecture decision

**Three-stage pipeline: deterministic atomize → vision-LLM structure assignment
(index-only) → deterministic assemble + validate.**

```
page.pdf
  │
  ├─► Sarvam full-page job (output_format=html)        [characters + first-pass layout]
  │        │
  │   [A] ATOMIZE (deterministic)
  │        parse HTML nesting → ordered atomic blocks:
  │        {id, row, col, cls, text}   text = character ground truth, never edited
  │
  ├─► 200 DPI page render (PyMuPDF)
  │        │
  │   [B] STRUCTURE ASSIGNMENT (vision LLM, Claude API)
  │        input:  page image + numbered block manifest (id, cls, head/tail snippets)
  │        output: ONLY indices — per block: {article_id, role, seq}
  │        roles: headline | subheading | body | caption | ad | masthead | table | drop
  │        The model never emits Telugu text → hallucination impossible by construction.
  │
  │   [C] ASSEMBLE (deterministic)
  │        group by article_id, order by seq, stitch mid-sentence fragments,
  │        attach captions separately, compute bbox (see §5), emit JSON
  │
  │   [D] VALIDATE (deterministic, no model)
  │        coverage / flow-continuity / dateline / caption-leak / order checks
  │        failures → flag article or page for human-in-the-loop review screen
  ▼
articles.json
```

### Why this is the right division of labor
Each component does the single thing it is reliable at:
- **Sarvam**: perfect Telugu glyphs AND (newly discovered, see §2) a genuinely good
  first-pass layout. It is wrong at the margins, not at the core.
- **Vision LLM**: page-level visual judgment — exactly the residual decisions Sarvam
  gets wrong (which `section-title` starts a new brief, where an article's body
  continues in another row, which fragment belongs to which article). It is NOT
  trusted with characters: it outputs block ids only.
- **Plain code**: assembly, stitching, bboxes, validation — all mechanical.

### Why the previous attempts failed (and what we keep)
- **Per-crop path (current `extract_articles.py`)**: OpenCV invented article
  boundaries from pixels (18–20 boxes, wrong), then per-crop OCR *inherited* those
  wrong boundaries and additionally injected AI image descriptions into body text
  (markdown mode describes photos). Geometry was deciding structure. Discarded.
- **Old full-page HTML parser**: walked `h1–h4/p` flat, ignored the
  `multi-column-row`/`column-block` nesting → collapsed the page to 5 articles.
  The signal was there; the parser threw it away. Replaced by [A].
- **Gutter detection (`column_strips.py`) / word-box reordering (`reorder_sarvam.py`)**:
  pure geometry, brittle on dense pages. Discarded. (The Telugu fragment-stitching
  idea from the docs is kept — it becomes a deterministic rule in [C].)

---

## 2. Evidence gathered in Phase 1 (do not re-derive)

Examined `artifacts/sarvam_fullpage.html` (one un-segmented Sarvam pass, this page):

1. **PDF is pure image.** No text layer (0 chars, 1 image, no fonts). All text must
   come from OCR.
2. **The HTML nesting is rich and mostly correct**:
   `page-body-container → multi-column-row cols-N → column-block → {h2.headline,
   h2.section-title, p.paragraph, figure.image, aside.advertisement, aside.footnote,
   div.table, p.page-number, header, footer}`.
3. **The exact `p1_a02` fusion failure does not exist here**: the fertigation
   article and the farmer Q&A sit in *separate* `multi-column-row` containers.
4. **AI image descriptions are quarantined in `alt` attributes** — 16 figures with
   alt text, **0 leaks inside `<p>` bodies**. Photo captions appear as
   `aside.footnote` at document end.
5. **Residual errors = exactly the LLM's job** (verified instances on this page):
   - Multiple articles per `column-block`, delimited only by headings: the
     murder-arrest block also contains the GO-17 protest and four-suicides items.
   - Cross-row continuation: చికెన్@340 headline in row 3, body tail in row 4
     col 3 (mixed into another block); భీమన్న క్షేత్రం tail starts mid-word
     ("న్నారు. క్యూలైన్లు…") in a different block.
   - Class errors: జంతుశాల news brief tagged `aside.advertisement`;
     "డీటీసీ పోస్టు భర్తీ అయ్యేనా?" is an article headline tagged `section-title`.
   - Orphan fragment above a headline: CM-relief-fund block starts with the tail
     of the school article.
   - OCR glitch: one heading rendered in Kannada script ("ರಾಜು" for రాజు) — characters
     stay as-is per constraints; structure assignment is unaffected.
6. **Stats for this page**: 25 `<h2>` (6 `headline`, 19 `section-title`), 71 `<p>`,
   23 figures, 9 asides, 1 table. ~95 atomic blocks → tiny LLM manifest.

---

## 3. Stage B contract (the only model call)

One Claude API call per page (model: `claude-opus-4-8`; downscale render to
~1200 px wide; adaptive thinking; temperature default).

**Input**: page image + manifest, one line per block:
`[17] row=2 col=1 cls=paragraph | head="• ఫర్టిగేషన్లో వాడే ఎరువులకు…" tail="…వాడాలి."`
(head ≈ first 60 chars, tail ≈ last 30 — enough to identify, cheap in tokens.)

**Output (strict JSON, validated by code)**:
```json
{"articles": [
   {"article_id": "a1",
    "blocks": [
       {"id": 5,  "role": "headline"},
       {"id": 7,  "role": "body", "seq": 1},
       {"id": 9,  "role": "body", "seq": 2, "continues_block": 7}
    ]}
 ],
 "drop": [{"id": 3, "reason": "masthead"}],
 "uncertain": [{"id": 41, "candidates": ["a4","a5"], "reason": "..."}]
}
```

**Rules baked into the prompt**: every block id must appear exactly once across
articles/drop/uncertain; no text output, ids only; captions/footnotes/figures →
role `caption` attached to nearest article; ads → role `ad`, excluded from audio;
`uncertain` is encouraged over guessing (feeds human review).

**Code enforces**: id coverage (bijection), JSON schema, role vocabulary. Any
violation → one retry with the error message, then page flagged.

---

## 4. Stage C/D rules (deterministic)

**Fragment stitching**: block B joins article-mate block A's tail iff A's text
lacks sentence-final punctuation (. ? ! ॥ ఆ-end) AND B starts lowercase-equivalent
(no bullet •/?/✓, no dateline). Join with single space; Telugu agglutination means
mid-word splits ("…చేస్తు" + "న్నారు…") concatenate without space when A ends in a
dangling consonant-vowel fragment (no trailing space in source).

**Validation checks (each → boolean + details, per article)**:
- `dateline_once`: the pattern `(న్యూస్టుడే|న్యూస్ టుడే|<place>,)` near body start
  appears at most once per article. Two datelines = fused articles
  (**this single check catches the p1_a02 failure automatically**).
- `caption_leak`: body must not contain `ఈ చిత్రంలో` or match any figure alt text
  (fuzzy ≥ 0.8) — catches AI-description injection.
- `flow_continuity`: every intra-article seam satisfies the stitching predicate;
  unmatched mid-sentence tail (article ends without sentence-final punct) → flag.
- `coverage`: Σ assigned paragraph chars ≥ 97% of HTML paragraph chars; no block
  assigned twice (hard fail).
- `order_sanity`: body seq must be monotone in (row, col-within-row) except where
  the LLM explicitly marked `continues_block` — wild jumps → flag.
- `headline_present`: every article has exactly one headline (briefs may promote a
  section-title; the LLM decides, code verifies non-empty).

Flagged articles → `"review": {"flags": [...], "uncertain": [...]}` in output,
consumed by the app's existing OCR-review screen.

## 5. bbox strategy
HTML carries no coordinates. Per-article bbox is computed by fuzzy-matching the
article's headline + first/last body lines against word boxes from a cheap local
Tesseract pass (`tel`, installed; its *characters* are never used, only geometry —
match via rapidfuzz partial ratio on normalized text). If no confident match:
bbox = null (the app treats bbox as optional). This keeps Sarvam as the only
paid OCR and adds zero new APIs.

## 6. Cost & generalization
- Per page: 1 Sarvam doc job (already in prod) + 1 Claude call
  (~1.5k image tokens + ~5k manifest in, ~2k out ≈ $0.04–0.08/page on Opus 4.8;
  Sonnet fallback ≈ 4× cheaper if quality holds).
- Nothing is tuned to this page: no pixel thresholds, no column counts, no
  Eenadu-specific geometry. Layout priors come from Sarvam's HTML (works on any
  newspaper it supports); judgment comes from the vision model; rules in §4 are
  language-level (Telugu sentence finals, dateline lexicon — extend per publication).

## 7. Phase breakdown (remaining)

| Phase | Build | Done signal |
|---|---|---|
| 2 — Core | `CHALLENGE/solution/pipeline.py`: [A] HTML→blocks parser, [B] Claude assigner (+ `--assignments file.json` manual mode for key-free runs), [C] assembler. Run on `page.pdf` via cached `sarvam_fullpage.html`. | `solution/articles.json` with ~18 correct articles; fertigation ≠ Q&A; no caption text in any body |
| 3 — Validation | `solution/validate.py` implementing §4; run against Phase 2 output AND against `artifacts/current_bad_output.json` (must catch p1_a02). | Old output fails `dateline_once`+`caption_leak`; new output passes |
| 4 — Generalisation | Run end-to-end (fresh Sarvam job) on a second page: `~/Downloads/Eenadu_TELANGANA_20260512.pdf` (full edition — pick a different page). No code changes allowed, only run. | Validator pass-rate comparable; misses documented |
| 5 — Integration | New `--ocr sarvam-structured` backend inside `extract_articles.py` calling the solution module; keep old modes intact. | CLI produces same JSON shape as legacy, app-compatible |

**Key env facts**: `SARVAM_API_KEY` in repo `.env` (works). `ANTHROPIC_API_KEY`
empty — Phase 2's live-API mode needs it; manual-assignments mode and cached-HTML
mode work without any key. Python: pymupdf, cv2, numpy installed; add rapidfuzz.

---

## Progress

### Phase 1 — DONE (this commit)
- Explored page image, Sarvam full-page HTML structure, PDF internals,
  prior pipeline failures. Evidence recorded in §2.
- Architecture decided (§1) with model contract (§3) and validation spec (§4).
- Next: **Phase 2** — build `CHALLENGE/solution/pipeline.py`. Start by re-using the
  Phase-1 outline parser (HTML → blocks) — reference snippet lives in git history
  of this session; it's ~30 lines with html.parser. Use cached
  `artifacts/sarvam_fullpage.html` (do NOT re-run Sarvam for page 1).

### Phase 2 — DONE
- `solution/pipeline.py`: [A] HTML→128 blocks, [B] Claude-API + manual assigner with
  id-bijection enforcement, [C] assembler with Telugu fragment stitching.
- `solution/assignments_page1.json`: Stage-B output (index-only) produced by the vision
  model from page image + manifest; continuation seams verified mid-word.
- `solution/articles.json`: **15 articles**, all correct headlines; murder article
  stitched across 2 columns reads continuously; farmer profile reordered
  44→46→47→45→48→49; 0 caption leaks; fertigation ≠ Q&A (p1_a02 fixed); 1 honest
  uncertain (orphan block 50); a10 జంతుశాల flagged (headline embedded in single block —
  needs finer atomization or review).
- Next: **Phase 3** — `solution/validate.py` per §4; must FAIL `current_bad_output.json`
  (catch p1_a02) and PASS `solution/articles.json`.

### Phase 3 — DONE
- `solution/validate.py`: caption_leak / fused_articles / dateline_midbody /
  flow_continuity / headline_present / order_sanity (flow-aware) / coverage.
- Old output: 44 flags; p1_a02 caught automatically (caption_leak +
  "4 datelines + 4 signatures in one body").
- New output: 12/15 PASS; all 4 remaining flags are TRUE positives (a1 dangling
  source fragment, a10 embedded headline+caption, a11 block-79 placement — the
  validator caught the assigner's own least-confident guess). 1 uncertain (block 50).
- Next: **Phase 4** — second page from ~/Downloads/Eenadu_TELANGANA_20260512.pdf
  (extract a different page with PyMuPDF, run live Sarvam HTML job via
  pipeline.py --pdf, then Stage-B assignment + validate; no code changes).

### Phase 4 — DONE
- Second page (full edition p2, state-news layout: crafts feature, briefs, accident,
  HC ruling, govt notices, quote boxes, weather table) run with ZERO code changes:
  `solution/page2_test/` — 104 blocks, 15 articles, 12/15 PASS, 3 true-positive
  flags (b2 graphic headline, b5 pull-quote punctuation, b15 lost tiny-font fragment).
- Cross-column continuations again resolved by seams (61'ఆ'+63, 63'సవ'+67'రించిన',
  84'వివరా'+87'లను'). Ads/notices (19 blocks) correctly dropped.
- Next: **Phase 5** — `--ocr sarvam-structured` backend in
  backend/extraction/extract_articles.py mapping solution output to legacy JSON shape.

### Phase 5 — DONE
- `--ocr sarvam-structured` added to `backend/extraction/extract_articles.py`
  (OCR_BACKENDS + extract() branch). Uses ANTHROPIC_API_KEY for live assignment or
  GATIVANI_ASSIGNMENTS=<file> for the key-free/manual path; without either it writes
  the block manifest and exits with instructions. Output is legacy-shape
  `articles.json` (app-compatible) plus `structured` (subheadings/captions/tables)
  and `uncertain` fields. Verified end-to-end against cached page-1 artifacts.

## Honest failure modes (deliverable #4)
1. **Sarvam loses text under tight layouts** (a1's dangling "వ్యర్ధంకావు," — the
   sentence tail under the photo never reached the HTML). Detected by
   flow_continuity; unrecoverable without a second OCR pass on the gap region.
2. **Headline fused inside one block** (a10 జంతుశాల: headline+body+embedded caption
   in a single aside). The index-only contract can't split a block. Detected by
   headline_missing; fix = finer atomization (sentence-level split of asides) or review.
3. **Graphic/stylized titles never reach OCR** (page-2 keychain craft headline).
   Detected by headline_missing.
4. **Assigner misjudgment on ambiguous continuations** (a11 block 79 placement).
   Detected by flow-aware order_sanity — the validator audits the model.
5. **Decorative tiny-font fragments lost** (page-2 Sadhguru quote middle). Detected
   by flow_continuity.
6. **Residual risk not yet covered**: a wrong-but-fluent assignment (two same-topic
   articles merged where the seam happens to read smoothly) can pass validation.
   Mitigation: double-run agreement diff (PLAN §4, optional) — not yet implemented.

All detected cases land in the `uncertain`/flags output consumed by the app's
existing OCR-review screen. Challenge deliverables 1–4 complete.
