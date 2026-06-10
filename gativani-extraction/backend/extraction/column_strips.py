#!/usr/bin/env python3
"""
column_strips.py — Option B: make layout the OCR's non-problem
==============================================================
Instead of asking Sarvam/Tesseract to understand a multi-column article,
cut the article into SINGLE-COLUMN strips and OCR them in reading order.
A single column is layout-trivial — any OCR reads it perfectly top-to-bottom.
Paragraph integrity at the seams is restored by reorder_sarvam.stitch rules.

Usage as a library:
    from column_strips import cut_strips, ocr_article_by_strips
    strips = cut_strips(article_crop)              # [(x0, img), ...] L->R
    paras  = ocr_article_by_strips(article_crop, ocr_fn)

ocr_fn signature: (numpy_image) -> str   (plug Sarvam, Tesseract, anything)

CLI demo (Tesseract):
    python column_strips.py article_crop.png
"""

from __future__ import annotations

import sys

import cv2
import numpy as np

from reorder_sarvam import ends_open, starts_open, join_lines, \
    BULLET_CHARS, DATELINE_RE

BULLET_CHARS = BULLET_CHARS + ("©", "*", "౦")


# ---------------------------------------------------------------------------
# Column detection inside ONE article crop
# ---------------------------------------------------------------------------

def _text_mask(crop: np.ndarray) -> np.ndarray:
    """Binarize to a text-ink mask, suppressing photos/solid graphics."""
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY) if crop.ndim == 3 else crop
    thr = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_MEAN_C,
                                cv2.THRESH_BINARY_INV, 25, 15)
    # Photos/halftones form huge solid components — remove anything whose
    # bounding box is "fat" (both wide and tall) relative to text size.
    n, labels, stats, _ = cv2.connectedComponentsWithStats(thr, 8)
    H, W = thr.shape
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if h > H * 0.12 and w > W * 0.12 and area > 0.4 * w * h:
            thr[labels == i] = 0
    # Remove long ruling lines so gutters stay clean
    h_k = cv2.getStructuringElement(cv2.MORPH_RECT, (max(W // 8, 40), 1))
    v_k = cv2.getStructuringElement(cv2.MORPH_RECT, (1, max(H // 8, 40)))
    lines = cv2.add(cv2.morphologyEx(thr, cv2.MORPH_OPEN, h_k),
                    cv2.morphologyEx(thr, cv2.MORPH_OPEN, v_k))
    return cv2.subtract(thr, lines)


def find_column_bounds(crop: np.ndarray,
                       n_bands: int = 14,
                       min_gutter_frac: float = 0.008,
                       min_col_frac: float = 0.07) -> list[tuple[int, int]]:
    """Return [(x0, x1), ...] column intervals, left -> right.

    Band-median projection: split the article into n_bands horizontal bands,
    mark per-band x-coverage, take the MEDIAN across bands. A true gutter is
    empty in most bands; a photo or spanning headline pollutes only its own
    2-3 bands and cannot bridge the gutter in the median.
    """
    mask = _text_mask(crop)
    H, W = mask.shape
    bands = np.array_split(mask, n_bands, axis=0)
    pres = np.stack([(b.sum(axis=0) > 0).astype(np.float32) for b in bands])
    med = np.median(pres, axis=0)
    covered = med > 0.5

    min_gutter = max(int(W * min_gutter_frac), 4)
    bounds, x = [], 0
    while x < W:
        if covered[x]:
            x0 = x
            while x < W:
                if covered[x]:
                    x += 1
                else:                          # bridge dips narrower than a gutter
                    j = x
                    while j < W and not covered[j]:
                        j += 1
                    if j - x >= min_gutter:
                        break
                    x = j
            bounds.append((x0, x))
        else:
            x += 1
    bounds = [(a, b) for a, b in bounds if (b - a) > W * min_col_frac]
    return bounds if bounds else [(0, W)]


def _ink_runs(row_ink: np.ndarray) -> list[tuple[int, int]]:
    on = row_ink > row_ink.max() * 0.05 if row_ink.max() else row_ink > 0
    runs, i = [], 0
    while i < len(on):
        if on[i]:
            j = i
            while j < len(on) and on[j]:
                j += 1
            runs.append((i, j))
            i = j
        else:
            i += 1
    return runs


def split_display_headline(crop: np.ndarray):
    """Separate display-headline glyphs from the body.

    Returns (headline_img_or_None, body_img):
      - headline_img: tight crop around display glyphs (~2.2x median glyph
        height), regardless of where they sit — they need NOT span the page.
      - body_img: the crop with those glyph regions painted white, so strip
        cutting and strip OCR never see headline fragments.
    """
    mask = _text_mask(crop)
    H, W = mask.shape
    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    comps = [(i, x, y, w, h) for i, (x, y, w, h, a)
             in enumerate(stats[1:], start=1) if h > 6 and w > 3 and a > 20]
    if len(comps) < 20:
        return None, crop
    med_h = sorted(c[4] for c in comps)[len(comps) // 2]
    display = [c for c in comps if c[4] > med_h * 2.2 and c[4] < H * 0.2]
    if len(display) < 2:
        return None, crop

    body = crop.copy()
    white = 255 if body.ndim == 2 else (255, 255, 255)
    for _, x, y, w, h in display:
        cv2.rectangle(body, (x - 2, y - 2), (x + w + 2, y + h + 2), white, -1)

    x0 = max(min(c[1] for c in display) - 4, 0)
    y0 = max(min(c[2] for c in display) - 4, 0)
    x1 = min(max(c[1] + c[3] for c in display) + 4, W)
    y1 = min(max(c[2] + c[4] for c in display) + 4, H)
    return crop[y0:y1, x0:x1], body


def cut_strips(crop: np.ndarray, pad: int = 4) -> list[tuple[int, np.ndarray]]:
    """Cut the article into single-column strips, returned left -> right.
    Element with x-offset -1 is the display-headline crop when present."""
    headline, body = split_display_headline(crop)
    H, W = body.shape[:2]
    out = []
    if headline is not None:
        out.append((-1, headline))
    for x0, x1 in find_column_bounds(body):
        a, b = max(x0 - pad, 0), min(x1 + pad, W)
        out.append((a, body[:, a:b]))
    return out


def stitch_column_texts(col_texts: list[str]) -> list[str]:
    """Merge per-column OCR outputs into complete paragraphs.
    Within a column, blank lines mark paragraph gaps. At each column seam,
    join only if the previous paragraph is linguistically open."""
    paras: list[str] = []
    for ci, text in enumerate(col_texts):
        first_in_col = True
        for rawline in text.splitlines():
            t = rawline.strip()
            if not t:
                first_in_col = False if first_in_col else first_in_col
                continue
            seam = first_in_col and ci > 0
            # Simple flow: same paragraph unless an explicit starter appears
            if not paras or t.startswith(BULLET_CHARS) or DATELINE_RE.match(t):
                paras.append(t)
            elif seam and not ends_open(paras[-1]) and not starts_open(t):
                paras.append(t)            # clean sentence boundary at seam
            else:
                paras[-1] = join_lines(paras[-1], t)
            first_in_col = False
    return paras


def ocr_article_by_strips(crop: np.ndarray, ocr_fn) -> list[str]:
    """Full Option-B path: cut -> OCR each strip in order -> stitch seams."""
    strips = cut_strips(crop)
    head = [t for x, img in strips if x == -1
            for t in [" ".join(ocr_fn(img).split())] if t]
    texts = [ocr_fn(img) for x, img in strips if x >= 0]
    return head + stitch_column_texts(texts)


# ---------------------------------------------------------------------------
# CLI demo with Tesseract
# ---------------------------------------------------------------------------

def _tesseract(img: np.ndarray) -> str:
    import pytesseract
    return pytesseract.image_to_string(img, lang="tel+eng", config="--psm 4")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    crop = cv2.imread(sys.argv[1])
    if crop is None:
        sys.exit(f"Cannot read {sys.argv[1]}")
    strips = cut_strips(crop)
    print(f"columns detected: {len(strips)} "
          f"(x-offsets: {[x for x, _ in strips]})")
    paras = ocr_article_by_strips(crop, _tesseract)
    print(f"\nparagraphs: {len(paras)}\n" + "=" * 60)
    for i, p in enumerate(paras, 1):
        print(f"\n[{i}] {p}")


if __name__ == "__main__":
    main()
