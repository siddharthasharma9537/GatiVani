# GatiVani — Newspaper Article Extraction Pipeline

Extracts complete, paragraph-intact articles from scanned Telugu newspaper
PDFs (Eenadu district editions) for the GatiVani newspaper-to-audio app.

## What's inside

```
backend/extraction/
  extract_articles.py    Page-level pipeline: render PDF @300 DPI, segment
                         article crops, OCR (tesseract|sarvam|claude),
                         output articles.json. CLI entry point.
  column_strips.py       Option B (default path): mask display headline,
                         cut single-column strips (band-median gutter vote),
                         OCR strips in order, stitch seams.
  reorder_sarvam.py      Option A: rebuild reading order from OCR word
                         boxes (geometry). Option C: Claude hybrid repair
                         (image + character-ground-truth text, fixes order
                         only) and a text-only linguistic jigsaw fallback.
docs/
  OCR_PARSING_INSTRUCTIONS.md   The spec. Column-aware reading order,
                         paragraph stitching rules (Telugu open-sentence
                         signals), island handling, validation checks, and
                         the ready-made Claude vision prompt.
samples/
  articles_sample.json   Real output from Eenadu Nalgonda 12-05-2026 pg 6.
  eenadu_articles_12-05-2026.txt   Same, formatted for reading.
  page_1_layout.jpg      Annotated segmentation visualization.
```

## Quick start (local, free)

```bash
pip install pymupdf opencv-python-headless numpy pytesseract requests
sudo apt install tesseract-ocr
# Telugu model (tessdata_best):
sudo curl -sL -o /usr/share/tesseract-ocr/5/tessdata/tel.traineddata \
  https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/main/tel.traineddata

python backend/extraction/extract_articles.py paper.pdf -o out/
```

Production: `--ocr sarvam` (SARVAM_API_KEY) or `--refine` to add the Claude
structuring pass (ANTHROPIC_API_KEY).

## Production flow

strips (B) by default → geometry (A) if Sarvam returns word boxes →
Claude hybrid repair (C) only for articles that fail §7 validation.

## Claude Code kickoff prompt

```
Read docs/OCR_PARSING_INSTRUCTIONS.md, then backend/extraction/
extract_articles.py, column_strips.py and reorder_sarvam.py. These
implement our Eenadu article extraction pipeline (strip-cutting by
default, geometry rebuild when Sarvam returns word boxes, Claude hybrid
repair for articles that fail validation). Integrate into the FastAPI
backend: add POST /extract that accepts a PDF, runs the pipeline with the
Sarvam backend (SARVAM_API_KEY env), and returns articles.json. Verify
the live Sarvam response format first (does it include word geometry?).
Don't change the stitching or validation logic.
```

## CLAUDE.md snippet

```
## Newspaper extraction pipeline
Article extraction lives in backend/extraction/. The full spec is in
docs/OCR_PARSING_INSTRUCTIONS.md — read it before touching extraction code.
```

## Known limits (be honest with yourself later)

- Raw Tesseract digits on newsprint can slip (saw రూ.340 → 810); the
  repair/refine pass or Sarvam handles number-critical text.
- Extreme feature crops (photo flanked by two narrow columns) may merge
  one strip — §7 validation flags it; escalate that crop to hybrid repair.
- SarvamOCR endpoint shape is per their docs but unverified against a
  live key; confirm whether responses include word bounding boxes.
