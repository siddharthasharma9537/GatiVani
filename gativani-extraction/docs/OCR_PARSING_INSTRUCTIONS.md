# Newspaper OCR & Parsing Instructions
## How to capture every article perfectly — keeping paragraphs intact across columns and rows

**For:** GatiVani extraction pipeline (Eenadu and similar Telugu dailies)
**Purpose:** These instructions tell an OCR system (code or vision-LLM) exactly how to read a
newspaper page so that every paragraph comes out whole — never broken, never mixed with a
neighbouring column, never interrupted by a caption or a table.

---

## 0. The one idea everything depends on

A newspaper page has **two different geometries** and OCR fails when it confuses them:

1. **Page geometry** — where ink physically sits (x, y coordinates).
2. **Story flow** — the order a human reads: *down* one column, then *jump up* to the
   top of the next column, **but only inside the same article's boundary**.

> **Golden rule: NEVER read horizontally across a column gutter.**
> A line of text ends at its column's right edge — the words printed at the same height
> in the next column belong to a *different sentence* (or a different article entirely).
> Reading "across the row" is the #1 cause of scrambled output.

Everything below exists to enforce this rule.

---

## 1. Establish the article boundary FIRST (before reading any text)

You must know where an article **starts and ends on the page** before you read a single word,
because column-jumping is only legal *inside* that boundary.

How to find the boundary:

1. **Ruled borders** — Eenadu separates articles with thin black rules and/or colored
   rounded boxes. A closed box = one article (or one furniture unit).
2. **Headline span** — a headline visually "owns" all columns beneath it until the next
   horizontal rule or the next headline. If a headline spans 3 columns, the article's body
   is exactly those 3 columns — column 4 at the same height is a different story.
3. **Whitespace walls** — a vertical white gutter that runs the full height of a text region
   with no text crossing it is a column separator; a *horizontal* white band wider than
   ~1.5 line-heights is usually an article separator.
4. **Dateline anchors** — every Eenadu item begins with the pattern
   `<ఊరు/desk>, న్యూస్‌టుడే:`. If a region contains **two or more datelines**, it is
   **two or more articles** — split it before reading.

**Output of this step:** a rectangle (or polygon) per article. All later steps operate on
one article-rectangle at a time, in isolation.

---

## 2. Map the columns INSIDE the article

Within one article rectangle:

1. Compute a **vertical ink projection** (sum of dark pixels per x-position).
2. Deep valleys = **gutters**. Text masses between gutters = **columns**.
   Eenadu briefs have 1 column; features have 2–6 narrow columns of equal width.
3. Number columns **left → right**: C1, C2, C3…
4. **Embedded islands** (photo, caption bar, fact-box, table, pull-quote, ad cut-in) are
   NOT columns. Detect them by: photos = low text density / halftone; boxes = tinted
   background or border; tables = grid of rules. **Cut islands out** of the column map —
   text wraps *around* them, and the wrap must not be read as a column break.

---

## 3. Reading order — the only legal path

```
Headline block (kicker → main headline → sub-deck)
   ↓
Dateline ("ఊరు, న్యూస్‌టుడే:")
   ↓
C1: top → bottom (every line, in order)
   ↓ (reached bottom of C1?)
C2: top → bottom
   ↓
C3: top → bottom … until last column
   ↓
Trailing byline ("— న్యూస్‌టుడే, జగిత్యాల")
   ↓
Islands LAST: caption(s), fact-box(es), table(s) — each as its own labeled unit
```

Rules that make this bulletproof:

- **R1 — Finish the column.** Never leave a column until its last line is read. Never
  return to a column once left.
- **R2 — Never cross the gutter mid-line.** Line segmentation must run per-column, with the
  column's own left/right edges as hard limits (in Tesseract terms: OCR each column crop
  separately; never feed a multi-column crop to a single-column page-segmentation mode).
- **R3 — Islands never interrupt.** If a caption or box sits between C2's text physically,
  body text from C2 continues around it — stitch the text *above* the island to the text
  *below* it, and move the island's own text to the end.
- **R4 — Respect the boundary.** When C-last ends, the article ends. Text below the
  bottom rule or right of the article box is the next story — do not append it.

---

## 4. Paragraph stitching — keeping every paragraph whole

This is the heart of the task. A paragraph may be split by (a) a line break, (b) a column
break, (c) an island, or (d) a page/zone jump. The stitching rules:

### 4.1 Within a column
- Consecutive lines belong to the same paragraph **unless** the new line starts with:
  a paragraph indent, a bullet (●, ★, ✦, ◆, ➤), a bold lead-in, or extra vertical
  spacing (> 1.4 × normal line gap).
- Join lines with a single space. Telugu does not hyphenate often, but if a line ends in
  a Latin hyphen `-` on a broken word, join with **no** space.

### 4.2 Across a column break (the critical case)
When the last line of column N is reached, decide: *does the paragraph continue into
column N+1?*

The paragraph **CONTINUES** (join last line of C_N + first line of C_N+1 into one
paragraph) when ANY of these is true:
- The last line does **not** end with terminal punctuation (`.` `!` `?` `…` `:` `॥`).
- The last line ends mid-word or with a connective/incomplete Telugu verb form
  (e.g., ends in `…ను`, `…కు`, `…లో`, `…గా`, `…చేసి`, `…అని` — case endings and
  non-finite forms that cannot end a sentence).
- The first line of the next column starts with a **lowercase-equivalent continuation**:
  no indent, no bullet, no bold lead-in, and begins mid-phrase.

The paragraph **ENDS** at the column break when:
- Last line ends with terminal punctuation **and** next column's first line is indented,
  bulleted, bolded, or starts a new dateline.

> **Worked example (from the fertigation article, 12-05-2026):**
> Column 3 ends: `…ఎరువులను ట్యాంకుల్లో కలిపే`
> Column 4 begins: `టప్పుడు ట్యాంకులో 50–70 శాతం నీళ్లుండేలా…`
> No terminal punctuation + broken word ⇒ JOIN:
> `…ఎరువులను ట్యాంకుల్లో కలిపేటప్పుడు ట్యాంకులో 50–70 శాతం నీళ్లుండేలా…`

### 4.3 Across an island (photo/caption/box in the middle)
Text above the island and text below the island in the **same column** are the same flow.
If the line above the island fails the "paragraph ends" test, join it directly to the
first line below the island. The island's text goes to its own unit (§5).

### 4.4 Bulleted paragraphs
A bullet (●) starts a new paragraph that may itself span columns. The bullet paragraph
ends only at the next bullet, a terminal-punctuated line followed by an indent, or the
article end. (The వివిధ రకాలైన… bullet on 12-05 ran a full column and ended at the
byline — it is ONE paragraph.)

### 4.5 Continuation across zones/pages
If the article ends with a continuation marker (మిగతా …లో / arrow) the JSON must record
`"continues": true` rather than silently truncating.

---

## 5. Islands: captions, boxes, tables — extract, label, never splice

| Island type | How to recognise | How to output |
|---|---|---|
| Photo caption | small/bold line(s) hugging a photo edge, often starts with a name or "…చిత్రంలో" | `captions: ["…"]` — NEVER merge into body |
| Fact/advisory box | tinted background, own mini-headline (సూచికలు, ఫిర్యాదు…) | separate `sidebars: [{title, body}]` |
| Table | grid rules, numeric columns (ధరలు, రకాలు) | structured `tables: [{headers, rows}]` — never flatten into prose |
| Pull-quote | large quoted text between rules | `pullquotes: […]` |
| Helpline / furniture | recurring template (మేమున్నాం.. మీకు తోడుగా, phone lists) | mark `type: "furniture"` — exclude from news flow |
| Ads / classifieds | display borders, prices, phone numbers, brand art | `type: "ad"` — exclude |

**Why this matters for TTS:** a caption read mid-sentence destroys the listener's thread.
In audio there is no "seeing past" a splice.

---

## 6. Headline assembly

Eenadu headlines are often **display art** (colored, multi-deck, stylised) that body-text
OCR misses. Capture them as a unit:

1. **Kicker** (small colored phrase above) + **main deck** + **sub-deck** = one headline
   string, joined with " .. " if the design splits them (e.g., `పెట్టుబడి ఆదా.. దిగుబడి హెచ్చు`).
2. The **dateline is not the headline.** `కరీంనగర్ కలెక్టరేట్, న్యూస్‌టుడే:` is metadata →
   `{"place": "...", "desk": "న్యూస్‌టుడే"}`.
3. If headline OCR confidence is low, re-OCR the headline strip alone at 2× scale, or
   pass that crop to the vision-LLM.

---

## 7. Validation — prove every paragraph is intact

Run these checks per article before accepting output; on failure, re-segment or escalate
that article crop to the LLM pass:

1. **Sentence-completeness:** every paragraph's final character is terminal punctuation
   (or the paragraph is a headline/caption/table cell).
2. **No orphan fragments:** no paragraph shorter than 4 words unless it is a bullet
   header, byline, or caption.
3. **Dateline uniqueness:** exactly one dateline per article (>1 ⇒ boundary error — split).
4. **Continuity smell-test:** no paragraph *begins* with a case-suffix fragment
   (`టప్పుడు…`, `న్నారు…`, `లో…`) — that signals an unjoined column break.
5. **Number audit:** digits (prices, dosages, dates, phone numbers) re-verified by a second
   pass (LLM or second OCR engine) — digit errors are the costliest for audio listeners.
6. **Coverage audit:** union of all extracted article boxes ≥ ~90% of text-ink on the
   page; anything unclaimed gets flagged for review.

---

## 8. Ready-to-use vision-LLM prompt (the `--refine` / `--ocr claude` pass)

Send ONE article crop per request with this prompt:

```
You are transcribing ONE article cropped from a Telugu newspaper (Eenadu).

READING ORDER — follow exactly:
1. The article has vertical columns. Read column 1 fully TOP to BOTTOM,
   then column 2 top to bottom, then column 3, left to right.
2. NEVER read across the white gutter between columns. Words at the same
   height in different columns are NOT the same sentence.
3. A sentence often breaks at the bottom of a column and continues at the
   TOP of the next column. JOIN it seamlessly into one paragraph. A Telugu
   sentence is incomplete unless it ends with . ! ? … or ॥ — if a column's
   last line lacks these, its continuation is at the top of the next column.
4. Photos, captions, tinted boxes and tables are ISLANDS. Body text flows
   AROUND them — stitch the text above and below an island together.
   Put island text in separate fields, never inside body paragraphs.
5. Do not include any text from outside this article's border.

OUTPUT — respond with ONLY this JSON, no markdown fences:
{
  "kicker": "",            // small phrase above headline, else ""
  "headline": "",          // full display headline, decks joined with " .. "
  "place": "",             // from the dateline, e.g. "జగిత్యాల"
  "body": ["para1", "para2", ...],   // COMPLETE paragraphs, in reading order
  "captions": [],
  "sidebars": [{"title": "", "body": ""}],
  "tables": [{"title": "", "headers": [], "rows": [[]]}],
  "byline": "",            // e.g. "న్యూస్‌టుడే, జగిత్యాల వ్యవసాయం"
  "language": "te",
  "continues": false       // true if article points to another page/zone
}

QUALITY RULES:
- Preserve Telugu script exactly; do not translate or summarise.
- Every body paragraph must be a complete unit — no paragraph may end
  mid-sentence and no paragraph may begin with a dangling suffix fragment.
- Transcribe ALL digits with extreme care (prices, doses, dates, phones).
- If part of the crop is illegible, write "[అస్పష్టం]" rather than guessing.
```

---

## 9. Quick reference card

1. Find the article's border **before** reading.
2. Map columns inside it; cut out islands.
3. Read: headline → dateline → C1↓ → C2↓ → … → byline → islands.
4. Join across column breaks when the sentence isn't finished.
5. Never cross a gutter sideways; never cross the article border.
6. Captions/boxes/tables are separate units — never spliced into body.
7. Validate: every paragraph ends with terminal punctuation; no fragment
   starts a paragraph; one dateline per article; digits double-checked.

Follow these and a paragraph that starts in column 1 and finishes in column 4
comes out as exactly one clean paragraph — every time, whether the article is
a single-column brief or a six-column display feature.
