# Extraction eval harness

Scores the CURRENT live state of an edition (whatever `documents-process-edition`
actually produced, fetched fresh from Supabase) against a hand-verified gold
file. Exists so a pipeline change can be measured against a real page instead
of eyeballed against a screenshot -- which is how every fix up to this point
got verified, and it does not scale past one page at a time.

## Usage

```bash
cp tools/eval/.env.example tools/eval/.env   # fill in SUPABASE_URL + SUPABASE_ANON_KEY
export $(cat tools/eval/.env | xargs)
node tools/eval/score.mjs tools/eval/ground-truth/nt-2026-07-26-p1.json <newspaper_id>
```

`SUPABASE_ANON_KEY` is the project's public anon/publishable key (the same one
the Flutter app ships with) -- not a secret, but still kept out of committed
files so `.env` doesn't need touching per project.

## What a gold file is

One JSON file per PAGE of one real edition. Each entry in `items` is one
printed item on that page: a headline, its body's opening words, where it
points if it continues elsewhere, and how confident the transcription is.

**Ground truth here comes from directly reading the rendered PDF page**, not
from trusting any previous pipeline output — including this session's own. Every
field marked `"confidence": "high"` was read off a 130-260 DPI render at the
time the gold file was written. `"confidence": "medium"` means it's plausible
but wasn't independently re-verified against a rendered page.

## What this harness does NOT yet check, and why

**Full-body character accuracy (CER).** The scorer supports a `gold_body`
field per item and will compute Levenshtein-based CER against it if present —
but no gold file currently populates it. Hand-transcribing full Telugu article
bodies from images is expensive and error-prone (my own transcription would
become the "ground truth," which isn't trustworthy for the metric that's
supposed to catch transcription errors). The two real options to fill this in:
a genuine independent human transcription of a few articles, or the dual-OCR
cross-check (Sarvam vs. Gemini reading the same region, scored by agreement)
discussed as the next real accuracy improvement -- that approach produces a
much larger, continuously-updating "second opinion" instead of a few
hand-typed reference articles.

**Exhaustive page coverage.** `nt-2026-07-26-p1.json` covers 16 of the items
visible on that page. One further item seen in earlier DB inspection
("చెల్లనికార్డులు.. చేతికి చిల్లు!") was NOT located in this pass's rendered
crops and was deliberately left out rather than guessed at. The scorer's
"unclaimed articles" report at the end of a run will surface anything on the
page that isn't accounted for in gold — that list is where coverage gaps like
this one show up.

## What it checks per item

- **recall** — was this printed item extracted as an article at all
- **visibility** — is it `processing_status='ready'` (would a reader actually see it)
- **body_start** — does the extracted body open with the right words (catches a
  wrong reading-order start, e.g. a sidebar's text sorted ahead of the real lede)
- **page_end_anchor** — for a lead that should continue elsewhere, is the
  page-1 portion's known ending actually present in the merged body (catches a
  truncated or reversed continuation)
- **continuation target** — does the article's recorded continuation/teaser
  placement point at the page it was actually printed to point at

That last check is the one this file's own gold data was built to catch: the
front-page flood story ("ఒడిసిపడ్తరా.. ఇడిసిపెడ్తరా?") points at page 5 per a
260 DPI zoom on the printed pointer digit, but the pipeline's last observed run
had merged in a different, similarly-worded flood story from page 8 instead —
a plausible title/vocabulary false-match, the same failure class as the earlier
NTPC/dateline bug. This is a real, previously unverified discrepancy, not a
confirmed bug: page 5's actual content was not independently checked, so
`score.mjs` will report it as `EXPECTED p5` and whatever the pipeline currently
does — verify that report before either fixing or dismissing it.

## Adding a new gold page

1. Render the real PDF page at 130+ DPI, read it directly (not from the app,
   not from a previous pipeline run — from the print).
2. For every distinct printed item: title (or note it's headless), the exact
   opening words of its body, and its page pointer if it has one.
3. Only write `"confidence": "high"` for what you actually zoomed in and read.
   `"medium"` or a `notes` field for anything inferred or reused from an
   earlier session.
4. Run the scorer and read the "unclaimed articles" list — that's your
   coverage check.
