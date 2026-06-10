#!/usr/bin/env python3
"""
GatiVani Newspaper Article Extractor
=====================================
Extracts individual news articles from scanned newspaper PDFs (Eenadu, etc.)
with zero embedded text. Pipeline:

    PDF ──► render @300 DPI ──► layout segmentation (OpenCV)
        ──► per-article OCR (Tesseract / Claude Vision)
        ──► structured JSON  { headline, body, bbox, lang, ... }

    Sarvam path (recommended for Telugu):
    PDF ──► Sarvam Document Intelligence (async job, full PDF)
        ──► structured HTML ──► article parser (multi-column-row aware)
        ──► structured JSON

Usage:
    python extract_articles.py input.pdf -o out/                       # local Tesseract (tel+eng)
    python extract_articles.py input.pdf -o out/ --ocr sarvam          # Sarvam: full PDF → HTML → parser (5-10 articles)
    python extract_articles.py input.pdf -o out/ --ocr sarvam-crops    # Sarvam: per-crop OCR via OpenCV segmentation (18-20 articles, slower)
    python extract_articles.py input.pdf -o out/ --ocr claude          # Claude Vision (ANTHROPIC_API_KEY env)
    python extract_articles.py input.pdf -o out/ --refine              # Tesseract + Claude cleanup pass

Dependencies:
    pip install pymupdf opencv-python-headless numpy pytesseract requests
    apt install tesseract-ocr  (+ tel.traineddata from tessdata_best for Telugu)
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path

import cv2
import numpy as np
import fitz  # PyMuPDF

# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class ArticleBlock:
    page: int
    article_id: str
    bbox: tuple[int, int, int, int]          # x, y, w, h (pixels @ render DPI)
    headline: str = ""
    body: str = ""
    raw_text: str = ""
    language: str = ""
    confidence: float = 0.0
    crop_path: str = ""

    def to_dict(self) -> dict:
        d = asdict(self)
        d["bbox"] = {"x": self.bbox[0], "y": self.bbox[1],
                     "w": self.bbox[2], "h": self.bbox[3]}
        return d


# ---------------------------------------------------------------------------
# Stage 1 — Render
# ---------------------------------------------------------------------------

def render_pages(pdf_path: Path, dpi: int) -> list[np.ndarray]:
    """Render every PDF page to a BGR numpy image."""
    doc = fitz.open(pdf_path)
    pages = []
    for page in doc:
        pix = page.get_pixmap(dpi=dpi, colorspace=fitz.csRGB)
        img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, 3)
        pages.append(cv2.cvtColor(img, cv2.COLOR_RGB2BGR))
    doc.close()
    return pages


def has_text_layer(pdf_path: Path) -> bool:
    """If the PDF already has real embedded text, OCR is unnecessary."""
    doc = fitz.open(pdf_path)
    chars = sum(len(p.get_text("text").strip()) for p in doc)
    doc.close()
    return chars > 200  # newspaper page with a real layer has thousands


# ---------------------------------------------------------------------------
# Stage 2 — Layout segmentation
# ---------------------------------------------------------------------------

def segment_articles(img: np.ndarray,
                     min_area_frac: float = 0.0008,
                     dilate_kernel: tuple[int, int] = (12, 8),
                     dilate_iter: int = 2) -> list[tuple[int, int, int, int]]:
    """
    Detect article-level text blocks on a newspaper page.

    Key trick for newspapers: column rules and box borders connect everything,
    so we *erase long horizontal/vertical lines first*, then dilate the
    remaining text mass into blobs and take their bounding boxes.
    """
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    H, W = gray.shape

    thr = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_MEAN_C,
                                cv2.THRESH_BINARY_INV, 25, 15)

    # 2a. Remove ruling lines (column separators / article box borders)
    h_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (max(W // 20, 40), 1))
    v_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (1, max(H // 20, 40)))
    lines = cv2.add(cv2.morphologyEx(thr, cv2.MORPH_OPEN, h_kernel),
                    cv2.morphologyEx(thr, cv2.MORPH_OPEN, v_kernel))
    clean = cv2.subtract(thr, lines)

    # 2b. Merge text lines into article blobs
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, dilate_kernel)
    blobs = cv2.dilate(clean, kernel, iterations=dilate_iter)

    cnts, _ = cv2.findContours(blobs, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    boxes = [cv2.boundingRect(c) for c in cnts]
    boxes = [b for b in boxes
             if b[2] * b[3] > min_area_frac * H * W
             and b[2] * b[3] < 0.25 * H * W   # skip blobs covering >25% of page (multi-article merges)
             and b[2] > 80 and b[3] > 50]

    return sort_reading_order(boxes, W)


def sort_reading_order(boxes: list, page_width: int) -> list:
    """
    Approximate newspaper reading order: cluster blocks into columns by
    x-center, read columns left→right, blocks within a column top→bottom.
    """
    if not boxes:
        return []
    col_width = page_width / 6  # Eenadu-style ~6 column grid
    def key(b):
        x, y, w, h = b
        col = int((x + w / 2) // col_width)
        return (col, y)
    return sorted(boxes, key=key)


# ---------------------------------------------------------------------------
# Stage 3 — OCR backends (pluggable)
# ---------------------------------------------------------------------------

class TesseractOCR:
    """Free, offline. Good baseline for Telugu newsprint."""
    def __init__(self, lang: str = "tel+eng"):
        self.lang = lang

    def ocr(self, crop: np.ndarray) -> tuple[str, float]:
        import pytesseract
        # Upscale small crops — Tesseract likes ≥30px x-height
        if crop.shape[0] < 300:
            crop = cv2.resize(crop, None, fx=1.5, fy=1.5,
                              interpolation=cv2.INTER_CUBIC)
        data = pytesseract.image_to_data(
            crop, lang=self.lang, config="--psm 4",
            output_type=pytesseract.Output.DICT)
        words, confs = [], []
        for txt, conf in zip(data["text"], data["conf"]):
            if txt.strip() and float(conf) > 0:
                words.append(txt)
                confs.append(float(conf))
        text = pytesseract.image_to_string(crop, lang=self.lang, config="--psm 4")
        avg_conf = (sum(confs) / len(confs) / 100.0) if confs else 0.0
        return text.strip(), avg_conf


class SarvamPipeline:
    """
    Sarvam AI Document Intelligence — full PDF path.

    Sends the entire PDF to Sarvam's async job API, receives structured HTML
    (multi-column-row layout), then parses it into articles using the same
    column-aware parser as the production Supabase edge function.

    Flow: create job → upload PDF (presigned Azure URL) → start → poll → download ZIP → parse HTML
    """
    BASE = "https://api.sarvam.ai"

    def __init__(self, api_key: str | None = None):
        import requests as _req
        self._req = _req
        self.api_key = api_key or os.environ.get("SARVAM_API_KEY", "")
        if not self.api_key:
            raise RuntimeError("Set SARVAM_API_KEY for --ocr sarvam")

    def _h(self) -> dict:
        return {"api-subscription-key": self.api_key}

    def run(self, pdf_path: Path) -> str:
        """Submit PDF, wait for completion, return raw HTML string."""
        import time, zipfile, io
        pdf_bytes = pdf_path.read_bytes()
        fname = pdf_path.name

        # 1. Create job
        r = self._req.post(f"{self.BASE}/doc-digitization/job/v1",
            headers={**self._h(), "Content-Type": "application/json"},
            json={"job_parameters": {"language": "te-IN", "output_format": "html"}},
            timeout=30)
        r.raise_for_status()
        job_id = r.json()["job_id"]
        print(f"   Sarvam job {job_id}")

        # 2. Get presigned upload URL
        r = self._req.post(f"{self.BASE}/doc-digitization/job/v1/upload-files",
            headers={**self._h(), "Content-Type": "application/json"},
            json={"job_id": job_id, "files": [fname]},
            timeout=30)
        r.raise_for_status()
        upload_info = next(iter(r.json()["upload_urls"].values()))
        metadata = upload_info.get("file_metadata") or {}

        # 3. PUT to presigned Azure Blob URL
        put_headers = {"x-ms-blob-type": "BlockBlob",
                       **{k: v for k, v in metadata.items() if isinstance(v, str)}}
        r = self._req.put(upload_info["file_url"], data=pdf_bytes,
                          headers=put_headers, timeout=300)
        r.raise_for_status()

        # 4. Start
        r = self._req.post(f"{self.BASE}/doc-digitization/job/v1/{job_id}/start",
            headers={**self._h(), "Content-Type": "application/json"},
            json={}, timeout=30)
        r.raise_for_status()

        # 5. Poll until completed
        for i in range(120):
            time.sleep(5)
            r = self._req.get(f"{self.BASE}/doc-digitization/job/v1/{job_id}/status",
                headers=self._h(), timeout=30)
            r.raise_for_status()
            state = r.json().get("job_state", "")
            print(f"   [{i*5}s] {state}")
            if state == "Completed":
                break
            if state in ("Failed", "Cancelled"):
                raise RuntimeError(f"Sarvam job {state}")
        else:
            raise RuntimeError("Sarvam job timed out")

        # 6. Get presigned download URL
        r = self._req.post(f"{self.BASE}/doc-digitization/job/v1/{job_id}/download-files",
            headers={**self._h(), "Content-Type": "application/json"},
            json={}, timeout=30)
        r.raise_for_status()
        dl_info = next(iter(r.json()["download_urls"].values()))

        # 7. Download ZIP → extract HTML
        r = self._req.get(dl_info["file_url"], timeout=300)
        r.raise_for_status()
        zf = zipfile.ZipFile(io.BytesIO(r.content))
        for name in zf.namelist():
            if name.endswith(".html"):
                return zf.read(name).decode("utf-8", errors="replace")
        # Fallback: concatenate everything
        return "\n".join(zf.read(n).decode("utf-8", errors="replace") for n in zf.namelist())

    def _img_to_pdf_bytes(self, img: np.ndarray) -> bytes:
        """Convert a numpy BGR image to a single-page PDF."""
        ok, png_buf = cv2.imencode(".png", img)
        png_bytes = png_buf.tobytes()
        h, w = img.shape[:2]
        doc = fitz.open()
        page = doc.new_page(width=w, height=h)
        page.insert_image(page.rect, stream=png_bytes)
        pdf_bytes = doc.tobytes()
        doc.close()
        return pdf_bytes

    def ocr_crop(self, crop: np.ndarray, label: str = "crop") -> str:
        """Send a single image crop to Sarvam as its own job, return plain text."""
        import time, zipfile, io
        pdf_bytes = self._img_to_pdf_bytes(crop)
        fname = f"{label}.pdf"

        r = self._req.post(f"{self.BASE}/doc-digitization/job/v1",
            headers={**self._h(), "Content-Type": "application/json"},
            json={"job_parameters": {"language": "te-IN", "output_format": "md"}},
            timeout=30)
        r.raise_for_status()
        job_id = r.json()["job_id"]

        r = self._req.post(f"{self.BASE}/doc-digitization/job/v1/upload-files",
            headers={**self._h(), "Content-Type": "application/json"},
            json={"job_id": job_id, "files": [fname]}, timeout=30)
        r.raise_for_status()
        upload_info = next(iter(r.json()["upload_urls"].values()))
        metadata = upload_info.get("file_metadata") or {}
        put_headers = {"x-ms-blob-type": "BlockBlob",
                       **{k: v for k, v in metadata.items() if isinstance(v, str)}}
        self._req.put(upload_info["file_url"], data=pdf_bytes,
                      headers=put_headers, timeout=120).raise_for_status()

        self._req.post(f"{self.BASE}/doc-digitization/job/v1/{job_id}/start",
            headers={**self._h(), "Content-Type": "application/json"},
            json={}, timeout=30).raise_for_status()

        for _ in range(60):
            time.sleep(4)
            r = self._req.get(f"{self.BASE}/doc-digitization/job/v1/{job_id}/status",
                headers=self._h(), timeout=30)
            r.raise_for_status()
            state = r.json().get("job_state", "")
            if state == "Completed":
                break
            if state in ("Failed", "Cancelled"):
                return ""
        else:
            return ""

        r = self._req.post(f"{self.BASE}/doc-digitization/job/v1/{job_id}/download-files",
            headers={**self._h(), "Content-Type": "application/json"},
            json={}, timeout=30)
        r.raise_for_status()
        dl_info = next(iter(r.json()["download_urls"].values()))

        r = self._req.get(dl_info["file_url"], timeout=120)
        r.raise_for_status()
        zf = zipfile.ZipFile(io.BytesIO(r.content))
        for name in zf.namelist():
            content = zf.read(name).decode("utf-8", errors="replace")
            # Strip markdown/html tags → plain text
            # Strip base64 image data and HTML tags, clean whitespace
            content = re.sub(r"!\[.*?\]\(data:image[^)]*\)", "", content)
            content = re.sub(r"data:image\S+", "", content)
            text = re.sub(r"<[^>]+>", " ", content)
            text = re.sub(r"[#*_`~]+", "", text)
            text = re.sub(r"\s+", " ", text).strip()
            if text:
                return text
        return ""

    def parse_html(self, html: str, source_name: str) -> list[ArticleBlock]:
        """
        Parse Sarvam's structured HTML output into ArticleBlock list.
        Uses regex to walk h1-h4/p elements in document order (same approach
        as the production JS pipeline in test-pipeline.mjs).
        """
        articles: list[ArticleBlock] = []
        current_title = ""
        current_body_parts: list[str] = []

        def flush():
            nonlocal current_title, current_body_parts
            if not current_title:
                return
            body = " ".join(current_body_parts).strip()
            if len(body) > 60:
                articles.append(ArticleBlock(
                    page=1, article_id=f"a{len(articles)+1:02d}",
                    bbox=(0, 0, 0, 0),
                    headline=current_title, body=body,
                    raw_text=f"{current_title}\n{body}",
                    language=detect_language(body),
                    confidence=0.95,
                ))
            current_title = ""
            current_body_parts = []

        def strip_tags(h: str) -> str:
            h = re.sub(r"<br\s*/?>", " ", h)
            h = re.sub(r"<[^>]+>", "", h)
            h = h.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " ")
            h = re.sub(r"\s+", " ", h)  # collapse newlines + spaces
            return h.strip()

        # Strip noise: <style>, <figure>, base64 images, ads, tables
        clean = re.sub(r"<style[^>]*>[\s\S]*?</style>", "", html, flags=re.DOTALL)
        clean = re.sub(r"<figure[^>]*>[\s\S]*?</figure>", "", clean, flags=re.DOTALL)
        clean = re.sub(r'src="data:image[^"]*"', 'src=""', clean)
        clean = re.sub(r'<div[^>]*class="[^"]*advertisement[^"]*"[^>]*>[\s\S]*?</div>', "", clean, flags=re.DOTALL)
        clean = re.sub(r'<div[^>]*class="[^"]*table[^"]*"[^>]*>[\s\S]*?</div>', "", clean, flags=re.DOTALL)

        element_re = re.compile(r"<(h[1-4]|p)([^>]*)>([\s\S]*?)</\1>", re.IGNORECASE)
        for m in element_re.finditer(clean):
            tag, attrs, inner = m.group(1).lower(), m.group(2), m.group(3)
            cls_m = re.search(r'class="([^"]*)"', attrs)
            cls = cls_m.group(1) if cls_m else ""
            text = strip_tags(inner)
            if not text:
                continue

            is_headline = tag.startswith("h") and "headline" in cls
            is_section  = tag.startswith("h") and "section-title" in cls
            is_para     = tag == "p" and "paragraph" in cls

            if is_headline:
                flush()
                current_title = text[:120]
            elif is_section:
                is_subsection = len(text) > 25 or bool(re.search(
                    r"శిబిరం|శిక్షణ|కేంద్రం|పరిషత్|నిర్మాణ|\d", text))
                if current_title and current_body_parts and is_subsection:
                    t = text if text.endswith((".", "।।")) else text + "."
                    current_body_parts.append(t)
            elif is_para:
                if not current_title:
                    current_title = text[:120]
                else:
                    current_body_parts.append(text)

        flush()
        return articles


class ClaudeOCR:
    """
    Claude Vision — reads the crop AND structures it (headline vs body)
    in one shot. Highest quality for messy newsprint; costs API tokens.
    """
    def __init__(self, api_key: str | None = None,
                 model: str = "claude-sonnet-4-6"):
        self.api_key = api_key or os.environ.get("ANTHROPIC_API_KEY", "")
        if not self.api_key:
            raise RuntimeError("Set ANTHROPIC_API_KEY for --ocr claude")
        self.model = model

    PROMPT = (
        "This is a cropped article from a Telugu newspaper (Eenadu). "
        "Transcribe it exactly. Respond ONLY with JSON, no markdown fences: "
        '{"headline": "...", "body": "...", "language": "te|hi|en|mixed"} '
        "Preserve Telugu script faithfully. If the crop contains ads or "
        'classifieds rather than a news article, set "headline" to "" and '
        "put all text in body."
    )

    def ocr(self, crop: np.ndarray) -> tuple[str, float]:
        text, headline, lang = self.structured(crop)
        combined = f"{headline}\n{text}".strip()
        return combined, 0.98

    def structured(self, crop: np.ndarray) -> tuple[str, str, str]:
        import requests
        ok, buf = cv2.imencode(".jpg", crop, [cv2.IMWRITE_JPEG_QUALITY, 90])
        b64 = base64.b64encode(buf.tobytes()).decode()
        resp = requests.post(
            "https://api.anthropic.com/v1/messages",
            headers={"x-api-key": self.api_key,
                     "anthropic-version": "2023-06-01",
                     "content-type": "application/json"},
            json={
                "model": self.model,
                "max_tokens": 4000,
                "messages": [{
                    "role": "user",
                    "content": [
                        {"type": "image",
                         "source": {"type": "base64",
                                    "media_type": "image/jpeg",
                                    "data": b64}},
                        {"type": "text", "text": self.PROMPT},
                    ],
                }],
            },
            timeout=180,
        )
        resp.raise_for_status()
        raw = "".join(b.get("text", "") for b in resp.json()["content"])
        raw = re.sub(r"^```(json)?|```$", "", raw.strip(), flags=re.M).strip()
        try:
            j = json.loads(raw)
            return j.get("body", ""), j.get("headline", ""), j.get("language", "te")
        except json.JSONDecodeError:
            return raw, "", "te"


OCR_BACKENDS = {"tesseract": TesseractOCR, "sarvam": SarvamPipeline,
                "sarvam-crops": SarvamPipeline, "claude": ClaudeOCR}


# ---------------------------------------------------------------------------
# Stage 4 — Post-processing
# ---------------------------------------------------------------------------

TELUGU_RANGE = re.compile(r"[\u0C00-\u0C7F]")
DEVANAGARI_RANGE = re.compile(r"[\u0900-\u097F]")

def detect_language(text: str) -> str:
    te = len(TELUGU_RANGE.findall(text))
    hi = len(DEVANAGARI_RANGE.findall(text))
    en = len(re.findall(r"[A-Za-z]", text))
    counts = {"te": te, "hi": hi, "en": en}
    top = max(counts, key=counts.get)
    total = sum(counts.values()) or 1
    return top if counts[top] / total > 0.6 else "mixed"


def split_headline(text: str) -> tuple[str, str]:
    """Heuristic: first non-empty line is the headline if short enough."""
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if not lines:
        return "", ""
    if len(lines) == 1:
        return "", lines[0]
    head = lines[0]
    if len(head) <= 80:
        return head, "\n".join(lines[1:])
    return "", "\n".join(lines)


def clean_text(text: str) -> str:
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    # Drop noise-only lines (OCR artifacts from photos/graphics)
    lines = [ln for ln in text.splitlines()
             if not re.fullmatch(r"[\W_]{1,6}", ln.strip()) or not ln.strip()]
    return "\n".join(lines).strip()


# ---------------------------------------------------------------------------
# Pipeline driver
# ---------------------------------------------------------------------------

def extract(pdf_path: Path, out_dir: Path, ocr_name: str, dpi: int,
            lang: str, refine: bool, min_conf: float) -> list[ArticleBlock]:
    out_dir.mkdir(parents=True, exist_ok=True)

    # ── Sarvam-crops path: OpenCV segmentation + per-crop Sarvam OCR ──────────
    if ocr_name == "sarvam-crops":
        pipeline = SarvamPipeline()
        crops_dir = out_dir / "crops"
        crops_dir.mkdir(exist_ok=True)

        pages = render_pages(pdf_path, dpi)
        print(f"📄 Rendered {len(pages)} page(s) @ {dpi} DPI")
        articles: list[ArticleBlock] = []

        for pno, img in enumerate(pages, start=1):
            boxes = segment_articles(img)
            total = len(boxes)
            print(f"   page {pno}: {total} article crops → sending to Sarvam one by one")
            vis = img.copy()

            for i, (x, y, w, h) in enumerate(boxes, start=1):
                pad = 6
                crop = img[max(y-pad,0):y+h+pad, max(x-pad,0):x+w+pad]
                aid = f"p{pno}_a{i:02d}"
                cv2.imwrite(str(crops_dir / f"{aid}.png"), crop)
                print(f"   [{i}/{total}] {aid} ...", end=" ", flush=True)

                raw = pipeline.ocr_crop(crop, label=aid)
                raw = clean_text(raw)
                print(f"{len(raw)}c")

                if not raw:
                    continue
                headline, body = split_headline(raw)
                language = detect_language(raw)
                if not (headline or body):
                    continue

                articles.append(ArticleBlock(
                    page=pno, article_id=aid, bbox=(x, y, w, h),
                    headline=headline, body=body, raw_text=raw,
                    language=language, confidence=0.95,
                    crop_path=str((crops_dir / f"{aid}.png").relative_to(out_dir)),
                ))
                cv2.rectangle(vis, (x, y), (x+w, y+h), (0, 200, 0), 4)
                cv2.putText(vis, aid, (x+8, y+42),
                            cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 200, 0), 3)

            cv2.imwrite(str(out_dir / f"page_{pno}_layout.jpg"),
                        cv2.resize(vis, (vis.shape[1]//2, vis.shape[0]//2)))

        payload = {
            "source": pdf_path.name,
            "ocr_backend": "sarvam-crops",
            "dpi": dpi,
            "article_count": len(articles),
            "articles": [a.to_dict() for a in articles],
        }
        (out_dir / "articles.json").write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"✅ {len(articles)} articles → {out_dir / 'articles.json'}")
        return articles

    # ── Sarvam path: full PDF → structured HTML → article parser ──────────────
    if ocr_name == "sarvam":
        pipeline = SarvamPipeline()
        print(f"📄 Sending {pdf_path.name} to Sarvam Document Intelligence...")
        html = pipeline.run(pdf_path)
        # Save raw HTML for debugging
        (out_dir / "sarvam_output.html").write_text(html, encoding="utf-8")
        articles = pipeline.parse_html(html, pdf_path.name)
        payload = {
            "source": pdf_path.name,
            "ocr_backend": "sarvam",
            "dpi": None,
            "article_count": len(articles),
            "articles": [a.to_dict() for a in articles],
        }
        (out_dir / "articles.json").write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"✅ {len(articles)} articles → {out_dir / 'articles.json'}")
        return articles

    # ── Tesseract / Claude path: render → segment → per-crop OCR ──────────────
    crops_dir = out_dir / "crops"
    crops_dir.mkdir(exist_ok=True)

    if has_text_layer(pdf_path):
        print("ℹ️  PDF has an embedded text layer — consider pdftotext instead "
              "of OCR. Continuing with OCR pipeline anyway.")

    ocr = TesseractOCR(lang) if ocr_name == "tesseract" else ClaudeOCR()
    refiner = ClaudeOCR() if (refine and ocr_name != "claude") else None

    articles: list[ArticleBlock] = []
    pages = render_pages(pdf_path, dpi)
    print(f"📄 Rendered {len(pages)} page(s) @ {dpi} DPI")

    for pno, img in enumerate(pages, start=1):
        boxes = segment_articles(img)
        print(f"   page {pno}: {len(boxes)} article blocks")
        vis = img.copy()

        for i, (x, y, w, h) in enumerate(boxes, start=1):
            pad = 6
            crop = img[max(y - pad, 0): y + h + pad, max(x - pad, 0): x + w + pad]
            aid = f"p{pno}_a{i:02d}"
            crop_path = crops_dir / f"{aid}.png"
            cv2.imwrite(str(crop_path), crop)

            if isinstance(ocr, ClaudeOCR):
                body, headline, language = ocr.structured(crop)
                raw = f"{headline}\n{body}".strip()
                conf = 0.98
            else:
                raw, conf = ocr.ocr(crop)
                raw = clean_text(raw)
                headline, body = split_headline(raw)
                language = detect_language(raw)
                if refiner and raw:
                    body2, head2, language = refiner.structured(crop)
                    if body2:
                        headline, body, conf = head2, body2, 0.98

            if conf < min_conf or not (headline or body):
                continue

            articles.append(ArticleBlock(
                page=pno, article_id=aid, bbox=(x, y, w, h),
                headline=headline, body=body, raw_text=raw,
                language=language, confidence=round(conf, 3),
                crop_path=str(crop_path.relative_to(out_dir)),
            ))
            cv2.rectangle(vis, (x, y), (x + w, y + h), (0, 0, 255), 4)
            cv2.putText(vis, aid, (x + 8, y + 42),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)

        cv2.imwrite(str(out_dir / f"page_{pno}_layout.jpg"),
                    cv2.resize(vis, (vis.shape[1] // 2, vis.shape[0] // 2)))

    payload = {
        "source": pdf_path.name,
        "ocr_backend": ocr_name + ("+claude-refine" if refiner else ""),
        "dpi": dpi,
        "article_count": len(articles),
        "articles": [a.to_dict() for a in articles],
    }
    (out_dir / "articles.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"✅ {len(articles)} articles → {out_dir/'articles.json'}")
    return articles


def main():
    ap = argparse.ArgumentParser(description="Extract articles from newspaper PDFs")
    ap.add_argument("pdf", type=Path)
    ap.add_argument("-o", "--out", type=Path, default=Path("extracted"))
    ap.add_argument("--ocr", choices=list(OCR_BACKENDS), default="tesseract")
    ap.add_argument("--dpi", type=int, default=300)
    ap.add_argument("--lang", default="tel+eng",
                    help="Tesseract langs (tel+eng, tel+hin+eng, ...)")
    ap.add_argument("--refine", action="store_true",
                    help="Run Claude structuring pass on top of local OCR")
    ap.add_argument("--min-conf", type=float, default=0.30,
                    help="Drop blocks below this OCR confidence")
    args = ap.parse_args()

    if not args.pdf.exists():
        sys.exit(f"File not found: {args.pdf}")
    extract(args.pdf, args.out, args.ocr, args.dpi,
            args.lang, args.refine, args.min_conf)


if __name__ == "__main__":
    main()
