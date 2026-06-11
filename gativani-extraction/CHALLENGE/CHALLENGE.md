# Challenge: Design the path from newspaper page → audio-ready articles

**For:** Claude Fable 5.
**What I want:** Think from the ground up. Don't patch my pipeline — **design the right
approach from scratch** to achieve the project's aim, then prove it on one real page.

I'll show you what I've tried and exactly how it fails, but only as evidence of where the
hard parts are. **Treat none of it as the architecture.** If the right answer throws all
of it away, do that.

---

## How to work through this (read before starting)

**Explore the full project first if you need to.** The project root is
`/Users/siddharthapothulapati/Workspace/gativani/`. Read any file in it —
source code, docs, existing pipelines, sample outputs — if it helps you form a
better plan. Don't limit yourself to the `CHALLENGE/artifacts/` folder. The
whole codebase is context; use as much of it as you need.

**Work in phases. Commit each phase before moving to the next.**
This challenge is larger than one context window. Structure your work so that if
the window resets, the next session can pick up exactly where this one left off
without re-deriving anything.

Suggested phase structure (adapt if your design calls for something different):

| Phase | Deliverable | Done signal |
|---|---|---|
| 1 — Explore & Plan | A written plan saved to `CHALLENGE/PLAN.md`: architecture decision, tool/model choices, phase breakdown, why this beats the current approach | File exists and committed |
| 2 — Core extraction | Python module that takes `page.pdf` and produces the correct JSON for this one page | Runnable, output correct |
| 3 — Validation layer | Automated checks that detect column bleed, paragraph mixing, bad boundaries | Tests pass |
| 4 — Generalisation | Works on a second page without re-tuning | Demonstrated |
| 5 — Integration | Plugs into the existing GatiVani pipeline as a drop-in replacement for `extract_articles.py` | Wired up |

**At the start of each phase:** read `CHALLENGE/PLAN.md` and any prior phase
output to restore context, then continue.

**At the end of each phase:** write a brief status to `CHALLENGE/PLAN.md` under
a `## Progress` section (what's done, what's next, any key decisions made), and
commit everything with `git`. This is your checkpoint — the next session reads
this instead of redoing the thinking.

**If you hit a token/context limit mid-phase:** save whatever partial work
exists, update `CHALLENGE/PLAN.md` with exactly where you stopped, and commit.
The continuation session will resume from there.

---

---

## The aim
**GatiVani turns a printed newspaper into audio you can listen to.** A reader opens the
app, picks a newspaper (*Eenadu*, Telugu district edition), and listens to it article by
article — instead of reading.

For that to work, the engine must take a scanned page and produce **discrete, correctly
structured articles**: each with its headline, its sub-headings, and its body paragraphs
**in the order a human would actually read them**. The audio is only as good as that
structure — if articles merge, paragraphs scramble, or a photo caption gets read aloud
mid-sentence, the listen is broken.

So the real problem is: **reconstruct the human reading structure of a dense, multi-column
newspaper page.** That is what I want you to solve.

## What is and isn't already handled
- **Reading the glyphs is solved.** Sarvam OCR pulls the Telugu text off the page with
  high character accuracy. Assume you can get every word. Treat OCR text as **ground truth
  for *what the characters are*** — your job is not to re-recognize text.
- **Everything about *structure* is open.** Article boundaries, multi-column reading order,
  headline/sub-heading/body hierarchy, dropping photo captions and ads — none of it is
  reliably solved. This is the whole challenge, and the design is yours to invent.

You decide the architecture: how to find article regions, how to establish reading order,
how to classify headings vs body vs caption, how to use the page image vs the OCR text vs
geometry. Start from the aim, not from my code.

---

## The desired output
Per page, a JSON array of articles:
```json
{
  "headline": "...",
  "subheadings": ["...", "..."],
  "body_paragraphs": ["para 1", "para 2", "..."],   // correct human reading order
  "bbox": {"x":0,"y":0,"w":0,"h":0}
}
```

## Hard constraints (these bound any design)
- **Telugu stays exactly as printed** — never translate, never rewrite or "correct"
  characters. OCR text is ground truth for characters; you only decide **structure and
  order**. Any model used for layout may *segment and reorder* the OCR text but must not
  generate or alter glyphs.
- Must **generalize** across variable column counts, headlines that span columns, embedded
  photos/captions, and ads on the same page — not be tuned to this one layout.
- **Photo captions and AI image descriptions must not end up in body text** — drop them or
  label them separately.

---

## Prior art — what I tried and how it fails (evidence only, NOT a template)
My current pipeline: render PDF → OpenCV finds ~18–20 candidate boxes → OCR each crop →
emit JSON. It fails in four ways, all of them *structure*, none of them OCR:

1. **Column bleed** — body continues into the horizontally adjacent column instead of
   flowing down the current column first, then right. Reading order goes across rows when
   it should go down columns.
2. **Article boundaries wander** — articles merge together or split apart.
3. **No heading hierarchy** — headline, sub-headings, and body collapse into one flat
   stream; photo captions leak in.
4. **Paragraphs scramble** even inside a correct boundary.

**Concrete failure** (`artifacts/current_bad_output.json`, item `p1_a02`): one "article"
is actually *two real articles plus a caption*, in scrambled order — the fertigation
article **"పెట్టుబడి ఆదా.. దిగుబడి హెచ్చు"**, then mid-sentence an AI image description
*"ఈ చిత్రంలో నీలి రంగు ద్రవంతో నిండిన రెండు పెద్ద గ్లాసులు ఉన్నాయి…"* ("in this image, two
large glasses of blue liquid…"), then a **separate** farmer Q&A ("రైతు ప్రశ్న – శాస్త్రవేత్త
సమాధానం", numbered 1–8) — all fused into one body. That single example shows all four
failures at once.

---

## What you have to work with (in `artifacts/`, runnable with no API key)
| File | What it is |
|---|---|
| `page.pdf` | The source page — *Eenadu* Telangana, 2026-05-12, page 6. |
| `page_clean.png` | Clean 200 DPI full-page render (no boxes) — the page as an image. |
| `sarvam_fullpage.html` | One un-segmented Sarvam pass over the whole page: 25 `<h2>`, 71 `<p>`, semantic classes (`.paragraph`, `.advertisement`, `.answer`, `.figure`…), 23 figure placeholders. Base64 stripped. |
| `sarvam_fullpage_text.txt` | Same pass flattened to plain text (~26K chars). |
| `sarvam_ocr_per_crop.json` | Per-crop OCR `{crop_id, bbox, crop_image, sarvam_ocr_text}`. Character-accurate, but the crops come from the *failing* OpenCV segmentation — `p1_a02` already merges two articles. |
| `crops/p1_a*.png` | The 20 cropped regions referenced above. |
| `page_render_with_boxes.jpg` | The render with current OpenCV boxes drawn — shows the bad segmentation. |
| `extract_articles.py`, `column_strips.py`, `reorder_sarvam.py` | The current pipeline + abandoned experiments. **Reference only.** |
| `current_bad_output.json` | Current output — the failure described above. |

You may also assume **line/word bounding boxes** are obtainable from Sarvam if your design
wants finer geometry.

---

## What to deliver
1. **A plan, from the ground up** — your reasoning for how to reconstruct article
   boundaries, reading order, and heading hierarchy reliably on real newsprint. Say *why*
   this approach is right and where the leverage is. If it discards my current pipeline,
   say so and why.
2. **A working Python implementation** runnable on `page.pdf` end to end, producing the
   JSON above.
3. **Validation** — automated checks that would *catch* column bleed and paragraph mixing
   without a human eyeballing it (e.g. how would your system detect the `p1_a02` fusion?).
4. **Honest failure modes** — where your approach still breaks, and how you'd flag those
   pages for the app's human-in-the-loop review screen.

The page is dense, multi-column, with photos and ads. I want a design that holds up on
real newsprint — and I want your *fresh* take on the path, not a repair of mine.
