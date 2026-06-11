#!/usr/bin/env python3
"""
reorder_sarvam.py — Layout-aware re-ordering for layout-blind OCR output
========================================================================
Sarvam (or any OCR) nails *characters* but may scramble *reading order* on
multi-column newsprint. This module takes over the layout job.

Three entry points:

  A) reconstruct_from_geometry(words)
     Use when the OCR returns word/line BOUNDING BOXES.
     Rebuilds lines -> columns -> reading order -> stitched paragraphs.
     100% deterministic, no API calls.

  C1) reorder_with_claude(image_b64, raw_text)
     Hybrid repair: Claude sees the article IMAGE for layout and treats the
     OCR text as character ground-truth. Fixes ORDER ONLY — never characters.

  C2) reorder_text_only(fragments)
     Last-resort linguistic jigsaw when there is no image and no geometry:
     joins fragments whose "open edges" match (no terminal punctuation /
     dangling Telugu suffixes).

CLI:
  python reorder_sarvam.py geometry words.json            # A
  python reorder_sarvam.py hybrid crop.png sarvam.txt     # C1 (ANTHROPIC_API_KEY)
  python reorder_sarvam.py text sarvam.txt                # C2
"""

from __future__ import annotations

import base64
import json
import os
import re
import sys
from dataclasses import dataclass

# ---------------------------------------------------------------------------
# Telugu linguistic signals (§4 of OCR_PARSING_INSTRUCTIONS.md)
# ---------------------------------------------------------------------------

TERMINAL_PUNCT = tuple(".!?…:;॥")
BULLET_CHARS = tuple("●★✦◆➤•▪")

# A line ending in these is almost certainly mid-sentence (case endings,
# non-finite verb forms, connectives). Used as an *additional* open signal.
OPEN_END_SUFFIXES = (
    "ను", "కు", "కి", "లో", "గా", "తో", "పై", "నే", "ని",
    "అని", "చేసి", "వచ్చి", "వెళ్లి", "ఉండి", "కాగా", "అయితే",
    "మరియు", "లేదా", "కంటే", "వరకు", "నుంచి", "ద్వారా", "కోసం",
)

# A line *starting* with these fragments is a dangling continuation of the
# previous column's broken word — join with NO space.
GLUE_START_FRAGMENTS = (
    "టప్పుడు", "స్తున్నారు", "న్నారు", "స్తోంది", "తున్నాయి", "డుతుంది",
    "ంచారు", "ంచాలి", "యాలి", "స్తారు", "కుంటే", "నప్పుడు", "ేందుకు",
)

DATELINE_RE = re.compile(r"^[\u0C00-\u0C7F A-Za-z.()-]{2,40},\s*న్యూస్?\s*[\u0C00-\u0C7F]*\s*:")


def ends_open(text: str) -> bool:
    """True if this line/fragment cannot be the end of a sentence."""
    t = text.rstrip()
    if not t:
        return False
    if t.endswith(TERMINAL_PUNCT):
        return False
    if t.endswith("-"):
        return True
    last = re.split(r"\s+", t)[-1]
    if any(last.endswith(s) for s in OPEN_END_SUFFIXES):
        return True
    # No terminal punctuation at all -> open by default
    return True


def starts_open(text: str) -> bool:
    """True if this line/fragment cannot be the start of a sentence."""
    t = text.lstrip()
    if not t:
        return False
    if t.startswith(BULLET_CHARS):
        return False
    if DATELINE_RE.match(t):
        return False
    first = re.split(r"\s+", t)[0]
    return any(first.startswith(g) or first == g for g in GLUE_START_FRAGMENTS)


def join_lines(prev: str, nxt: str) -> str:
    """Join two lines of one paragraph with correct spacing."""
    p, n = prev.rstrip(), nxt.lstrip()
    if p.endswith("-"):                       # explicit hyphen break
        return p[:-1] + n
    first = re.split(r"\s+", n)[0] if n else ""
    if any(first.startswith(g) for g in GLUE_START_FRAGMENTS):
        return p + n                          # broken Telugu word -> no space
    return p + " " + n


# ---------------------------------------------------------------------------
# Option A — geometric reconstruction
# ---------------------------------------------------------------------------

@dataclass
class Word:
    text: str
    x: float
    y: float
    w: float
    h: float

    @property
    def cx(self): return self.x + self.w / 2
    @property
    def cy(self): return self.y + self.h / 2


@dataclass
class Line:
    words: list

    @property
    def text(self): return " ".join(w.text for w in self.words)
    @property
    def x(self): return min(w.x for w in self.words)
    @property
    def x2(self): return max(w.x + w.w for w in self.words)
    @property
    def y(self): return min(w.y for w in self.words)
    @property
    def cy(self): return sum(w.cy for w in self.words) / len(self.words)
    @property
    def h(self): return max(w.y + w.h for w in self.words) - self.y
    @property
    def width(self): return self.x2 - self.x


def words_to_lines(words: list[Word]) -> list[Line]:
    """Cluster words into text lines by vertical-centre proximity."""
    if not words:
        return []
    med_h = sorted(w.h for w in words)[len(words) // 2]
    tol = med_h * 0.6
    lines: list[list[Word]] = []
    for w in sorted(words, key=lambda w: w.cy):
        placed = False
        for ln in lines:
            ref = sum(x.cy for x in ln) / len(ln)
            if abs(w.cy - ref) <= tol:
                ln.append(w)
                placed = True
                break
        if not placed:
            lines.append([w])
    out = [Line(sorted(ln, key=lambda w: w.x)) for ln in lines]
    return sorted(out, key=lambda l: l.y)


def detect_column_intervals_words(words: list[Word], min_gutter: float) -> list[tuple]:
    """Column intervals via x-coverage histogram.

    A true gutter has ~zero ink coverage across the column's full height;
    a mere word gap does not (other rows cover it). This survives the odd
    noisy box that bridges a gutter — unlike naive interval merging."""
    import numpy as np
    W = int(max(w.x + w.w for w in words)) + 2
    cov = np.zeros(W)
    for w in words:
        a, b = int(max(w.x, 0)), int(min(w.x + w.w, W))
        cov[a:b] += w.h
    k = max(int(min_gutter // 2), 1)
    cov = np.convolve(cov, np.ones(k) / k, mode="same")
    floor = np.median(cov[cov > 0]) * 0.06 if (cov > 0).any() else 0
    covered = cov > floor

    cols, x = [], 0
    while x < W:
        if covered[x]:
            x0 = x
            while x < W:
                if covered[x]:
                    x += 1
                else:                       # tolerate sub-gutter dips
                    j = x
                    while j < W and not covered[j]:
                        j += 1
                    if j - x >= min_gutter:
                        break
                    x = j
            cols.append((x0, x))
        else:
            x += 1
    med_w = sorted(b - a for a, b in cols)[len(cols) // 2] if cols else 0
    cols = [(a, b) for a, b in cols if (b - a) > med_w * 0.35]
    return cols or [(0, W)]


def reading_order(words: list[Word]) -> tuple[list[Line], list[int]]:
    """Return lines in true reading order + parallel seam flags.

    Order of operations matters:
      1. Split DISPLAY glyphs (headline art, ~2x body height) from body words.
      2. Detect column intervals from BODY words only.
      3. Build lines PER COLUMN (never across gutters).
      4. Emit: headline lines (by y), then col 1 top->bottom, col 2, ...
    """
    if not words:
        return [], []
    hs = sorted(w.h for w in words)
    med_h = hs[len(hs) // 2]

    display = [w for w in words if w.h > med_h * 1.9]
    body = [w for w in words if w.h <= med_h * 1.9] or words

    # Drop garbage boxes: a body-height word spanning ~4x the median word
    # width is an OCR artifact (it can bridge several gutters and destroy
    # column detection).
    ws = sorted(w.w for w in body)
    med_w = ws[len(ws) // 2]
    body = [w for w in body if w.w <= med_w * 4] or body

    cols = detect_column_intervals_words(body, min_gutter=med_h * 0.8)

    def col_of(w: Word) -> int:
        best, score = 0, -1.0
        for i, (a, b) in enumerate(cols):
            ov = max(0.0, min(w.x + w.w, b) - max(w.x, a))
            if ov > score:
                best, score = i, ov
        return best

    by_col: dict[int, list[Word]] = {i: [] for i in range(len(cols))}
    for w in body:
        by_col[col_of(w)].append(w)

    ordered: list[Line] = []
    seams: list[int] = []
    for l in words_to_lines(display):            # headline decks first, by y
        ordered.append(l)
        seams.append(1)
    for i in range(len(cols)):
        col_lines = words_to_lines(by_col[i])    # per-column clustering only
        for j, l in enumerate(col_lines):
            ordered.append(l)
            if j == 0:
                seams.append(2)                  # column seam
            else:
                gap = l.y - (col_lines[j - 1].y + col_lines[j - 1].h)
                seams.append(1 if gap > med_h * 0.9 else 0)
    return ordered, seams


def stitch(ordered: list[str], seams: list[int]) -> list[str]:
    """seams: 0 = same-column next line, 1 = visual paragraph gap,
    2 = column seam (join only if previous line is linguistically open)."""
    paras: list[str] = []
    for text, seam in zip(ordered, seams):
        t = text.strip()
        if not t:
            continue
        new_para = (
            not paras
            or t.startswith(BULLET_CHARS)
            or DATELINE_RE.match(t)
            or (seam == 1 and not starts_open(t))
            or (seam == 2 and not ends_open(paras[-1]) and not starts_open(t))
        )
        if new_para:
            paras.append(t)
        else:
            paras[-1] = join_lines(paras[-1], t)
    return [p for p in paras
            if len(re.sub(r'[\\W_]', '', p)) > 2 or DATELINE_RE.match(p)]


def reconstruct_from_geometry(words_in: list[dict]) -> dict:
    """words_in: [{"text","x","y","w","h"}, ...] in ANY order (e.g. shuffled
    Sarvam output). Returns {"paragraphs": [...complete, ordered...]}."""
    words = [Word(d["text"], float(d["x"]), float(d["y"]),
                  float(d["w"]), float(d["h"]))
             for d in words_in if str(d.get("text", "")).strip()]
    ordered, seams = reading_order(words)
    return {"paragraphs": stitch([l.text for l in ordered], seams)}


# ---------------------------------------------------------------------------
# Option C1 — hybrid repair (image = layout truth, OCR text = character truth)
# ---------------------------------------------------------------------------

HYBRID_PROMPT = """You are fixing the READING ORDER of an OCR transcription \
from ONE Telugu newspaper article. The attached image shows the article's \
true layout. The transcription below has highly accurate CHARACTERS but its \
lines may be in the wrong order (the OCR was not column-aware).

YOUR ONLY JOB IS ORDER AND JOINING:
1. Columns read top-to-bottom, then left to right. Never read across the \
white gutter between columns.
2. A sentence broken at a column's bottom continues at the NEXT column's \
top — join the two fragments into one paragraph (a Telugu sentence is \
incomplete unless it ends with . ! ? … or ॥).
3. Captions, tinted boxes and tables are separate units, never inside body \
paragraphs.
4. DO NOT change, add, correct or delete ANY character or digit from the \
transcription. If the transcription disagrees with the image, TRUST THE \
TRANSCRIPTION. Only re-order and join.

OCR TRANSCRIPTION (character ground-truth):
<<<
{raw_text}
>>>

Respond with ONLY this JSON, no markdown fences:
{{"headline": "", "place": "", "body": ["para1", "para2"],
  "captions": [], "sidebars": [{{"title": "", "body": ""}}],
  "byline": "", "notes": ""}}"""


def reorder_with_claude(image_b64: str, raw_text: str,
                        model: str = "claude-sonnet-4-6",
                        media_type: str = "image/png") -> dict:
    import requests
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        raise RuntimeError("Set ANTHROPIC_API_KEY for hybrid reorder")
    resp = requests.post(
        "https://api.anthropic.com/v1/messages",
        headers={"x-api-key": api_key,
                 "anthropic-version": "2023-06-01",
                 "content-type": "application/json"},
        json={"model": model, "max_tokens": 4000,
              "messages": [{"role": "user", "content": [
                  {"type": "image", "source": {"type": "base64",
                   "media_type": media_type, "data": image_b64}},
                  {"type": "text",
                   "text": HYBRID_PROMPT.format(raw_text=raw_text)}]}]},
        timeout=180)
    resp.raise_for_status()
    raw = "".join(b.get("text", "") for b in resp.json()["content"])
    raw = re.sub(r"^```(json)?|```$", "", raw.strip(), flags=re.M).strip()
    return json.loads(raw)


# ---------------------------------------------------------------------------
# Option C2 — text-only linguistic jigsaw (no image, no geometry)
# ---------------------------------------------------------------------------

def reorder_text_only(fragments: list[str]) -> list[str]:
    """Greedy repair: keep given order, but when a fragment has an open end,
    look ahead for the unique fragment with a matching open start and pull
    it next. Conservative — only moves a fragment when the match is
    unambiguous."""
    frags = [f.strip() for f in fragments if f.strip()]
    out, used = [], [False] * len(frags)
    i = 0
    while i < len(frags):
        if used[i]:
            i += 1
            continue
        used[i] = True
        chain = frags[i]
        while ends_open(chain):
            cands = [j for j, f in enumerate(frags)
                     if not used[j] and starts_open(f)]
            if len(cands) != 1:
                break
            used[cands[0]] = True
            chain = join_lines(chain, frags[cands[0]])
        out.append(chain)
        i += 1
    return out


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    mode = sys.argv[1]
    if mode == "geometry":
        words = json.load(open(sys.argv[2], encoding="utf-8"))
        print(json.dumps(reconstruct_from_geometry(words),
                         ensure_ascii=False, indent=2))
    elif mode == "hybrid":
        img_b64 = base64.b64encode(open(sys.argv[2], "rb").read()).decode()
        raw = open(sys.argv[3], encoding="utf-8").read()
        mt = "image/jpeg" if sys.argv[2].lower().endswith((".jpg", ".jpeg")) \
             else "image/png"
        print(json.dumps(reorder_with_claude(img_b64, raw, media_type=mt),
                         ensure_ascii=False, indent=2))
    elif mode == "text":
        frags = [ln for ln in open(sys.argv[2], encoding="utf-8")
                 .read().split("\n\n")]
        print(json.dumps({"paragraphs": reorder_text_only(frags)},
                         ensure_ascii=False, indent=2))
    else:
        sys.exit(f"Unknown mode: {mode}")


if __name__ == "__main__":
    main()
