#!/usr/bin/env python3
"""
GatiVani structured extraction — ground-up design (see ../PLAN.md).

Stages:
  [A] atomize  : Sarvam full-page HTML -> ordered atomic blocks (character ground truth)
  [B] assign   : vision LLM (or manual JSON) maps block ids -> {article_id, role, seq}
                 The model outputs ONLY indices, never text -> no hallucination possible.
  [C] assemble : deterministic grouping, Telugu fragment stitching, captions separated

Usage:
  python pipeline.py --html artifacts/sarvam_fullpage.html --manifest          # print manifest
  python pipeline.py --html ... --assignments assignments.json -o articles.json # manual mode
  python pipeline.py --pdf page.pdf --anthropic -o articles.json               # live mode
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field, asdict
from html.parser import HTMLParser
from pathlib import Path

# ---------------------------------------------------------------- [A] ATOMIZE

ATOMIC_TAGS = {"h1", "h2", "h3", "h4", "p", "figure", "aside", "table"}
CONTAINER_CLASSES = ("multi-column-row", "column-block")

SENTENCE_FINAL = re.compile(r"[.?!।॥…]\s*$|[.?!।॥…]['\"’”\)]\s*$")
OPENER = re.compile(r"^\s*[•▪●★☞✓?]|^\s*\d+[.)]\s")
DATELINE = re.compile(r"న్యూస్\s?టుడే|న్యూస్\s?టుడే,|నేటి నుంచి|^[ఀ-౿]+\s*\([ఀ-౿]+\)\s*[:,]")
AI_DESC = re.compile(r"ఈ చిత్రంలో")


@dataclass
class Block:
    id: int
    row: int        # index of multi-column-row in document order; -1 = outside rows
    col: int        # index of column-block within its row; -1 = outside
    cls: str        # headline | section-title | paragraph | image | advertisement |
                    # footnote | table | page-number | header | footer
    text: str       # character ground truth — NEVER edited downstream
    alt: str = ""   # figure alt (AI image description) — quarantined, never in body


class _SarvamHTML(HTMLParser):
    """Walks Sarvam's nested HTML and emits Blocks in document order."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks: list[Block] = []
        self.row = -1
        self.col = -1
        self._row_count = 0
        self._col_count = 0
        self._stack: list[str] = []          # container tags currently open
        self._cur: tuple[str, str, str] | None = None  # (tag, cls, alt)
        self._buf: list[str] = []
        self._depth_in_atomic = 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = (a.get("class") or "").strip()
        if self._cur is not None:
            # nested tag inside an atomic element (e.g. <td>, <br>) — keep collecting text
            if tag == "br":
                self._buf.append(" ")
            if tag in ("td", "th", "tr"):
                self._buf.append(" ")
            self._depth_in_atomic += 1
            return
        if tag == "div" and cls.startswith("multi-column-row"):
            self.row = self._row_count
            self._row_count += 1
            self._col_count = 0
            self._stack.append("row")
        elif tag == "div" and cls == "column-block":
            self.col = self._col_count
            self._col_count += 1
            self._stack.append("col")
        elif tag in ATOMIC_TAGS or (tag == "div" and cls == "table"):
            base = cls.split()[0] if cls else tag
            self._cur = (tag, base, a.get("alt", ""))
            self._buf = []
            self._depth_in_atomic = 0
        elif tag in ("header", "footer"):
            self._cur = (tag, tag, "")
            self._buf = []
            self._depth_in_atomic = 0
        elif tag == "img" and self._cur is None:
            # stray img outside figure
            self.blocks.append(Block(len(self.blocks), self.row, self.col,
                                     "image", "", a.get("alt", "")))

    def handle_endtag(self, tag):
        if self._cur is not None:
            if self._depth_in_atomic > 0 and tag != self._cur[0]:
                self._depth_in_atomic -= 1
                return
            if tag == self._cur[0]:
                t, cls, alt = self._cur
                text = re.sub(r"\s+", " ", "".join(self._buf)).strip()
                self.blocks.append(Block(len(self.blocks), self.row, self.col,
                                         cls, text, alt))
                self._cur = None
                return
        if self._stack and tag == "div":
            top = self._stack.pop()
            if top == "row":
                self.row = -1
                self.col = -1
            elif top == "col":
                self.col = -1

    def handle_data(self, data):
        if self._cur is not None:
            self._buf.append(data)


def parse_blocks(html: str) -> list[Block]:
    p = _SarvamHTML()
    p.feed(html)
    # Drop empty non-figure blocks and boilerplate
    out = []
    for b in p.blocks:
        if b.cls in ("header", "footer", "page-number"):
            continue
        if not b.text and not b.alt and b.cls != "image":
            continue
        out.append(b)
    # re-number after filtering so ids are dense and stable
    for i, b in enumerate(out):
        b.id = i
    return out


# ------------------------------------------------------------- [B] MANIFEST

def manifest(blocks: list[Block], head=72, tail=32) -> str:
    lines = []
    for b in blocks:
        t = b.text
        if len(t) <= head + tail:
            snippet = f'"{t}"'
        else:
            snippet = f'"{t[:head]}…" tail="…{t[-tail:]}"'
        extra = f' alt="{b.alt[:50]}…"' if b.alt and not t else ""
        lines.append(f"[{b.id}] row={b.row} col={b.col} cls={b.cls} {snippet}{extra}")
    return "\n".join(lines)


PROMPT = """You are reconstructing the human reading structure of a Telugu newspaper page.

You are given the page IMAGE and a MANIFEST of atomic text blocks extracted by OCR.
Each block has an id, its (row, col) position in the OCR's column layout, a CSS class
hint (headline / section-title / paragraph / advertisement / footnote / image / table),
and the first/last characters of its text.

Your job is STRUCTURE ONLY. Output ids — never any Telugu text.

Assign every block id to exactly one of:
- an article, with role: "headline" | "subheading" | "body" | "caption" | "table"
- the drop list, with reason: "ad" | "masthead" | "noise"

Rules:
- An article = one news item a human would read as a unit. Use the image to decide
  boundaries: a column-block may contain several articles; an article's body may
  continue in a different row/column (follow the visual flow).
- "seq" gives body reading order within the article (1, 2, 3, …). If a block visually
  continues another block mid-sentence, add "continues_block": <id>.
- class hints can be wrong (a headline may be tagged section-title; a news brief may
  be tagged advertisement). Trust the image over the hint.
- figure blocks and footnote blocks are captions ("caption") attached to the article
  whose photo they describe, or drop as noise if decorative.
- If genuinely unsure where a block belongs, put it in "uncertain" with candidate
  article ids — do NOT guess silently.

Return ONLY this JSON:
{"articles":[{"article_id":"a1","blocks":[{"id":5,"role":"headline"},
 {"id":7,"role":"body","seq":1},{"id":9,"role":"body","seq":2,"continues_block":7}]}],
 "drop":[{"id":3,"reason":"masthead"}],
 "uncertain":[{"id":41,"candidates":["a4","a5"],"reason":"…"}]}

MANIFEST:
"""


def assign_with_anthropic(blocks: list[Block], page_png: Path, model: str) -> dict:
    import base64
    import anthropic
    client = anthropic.Anthropic()
    img_b64 = base64.standard_b64encode(page_png.read_bytes()).decode()
    msg_content = [
        {"type": "image", "source": {"type": "base64", "media_type": "image/png",
                                     "data": img_b64}},
        {"type": "text", "text": PROMPT + manifest(blocks)},
    ]
    last_err = ""
    for attempt in range(2):
        content = msg_content if not last_err else msg_content + [
            {"type": "text", "text": f"Your previous answer was invalid: {last_err}. "
                                     f"Return corrected JSON only."}]
        with client.messages.stream(
            model=model,
            max_tokens=8000,
            thinking={"type": "adaptive"},
            messages=[{"role": "user", "content": content}],
        ) as stream:
            resp = stream.get_final_message()
        txt = "".join(c.text for c in resp.content if c.type == "text")
        m = re.search(r"\{.*\}", txt, re.S)
        try:
            data = json.loads(m.group(0)) if m else json.loads(txt)
            err = check_assignment(blocks, data)
            if not err:
                return data
            last_err = err
        except (json.JSONDecodeError, AttributeError) as e:
            last_err = f"JSON parse error: {e}"
    raise RuntimeError(f"assignment invalid after retry: {last_err}")


def check_assignment(blocks: list[Block], data: dict) -> str:
    """Return '' if valid, else error description. Enforces id bijection + vocab."""
    ids = {b.id for b in blocks}
    seen: dict[int, str] = {}
    roles = {"headline", "subheading", "body", "caption", "table"}
    for art in data.get("articles", []):
        for blk in art.get("blocks", []):
            i = blk.get("id")
            if i not in ids:
                return f"unknown id {i}"
            if i in seen:
                return f"id {i} assigned twice ({seen[i]} and {art['article_id']})"
            if blk.get("role") not in roles:
                return f"bad role {blk.get('role')!r} on id {i}"
            seen[i] = art["article_id"]
    for d in data.get("drop", []):
        i = d.get("id")
        if i in seen:
            return f"id {i} both dropped and assigned"
        seen[i] = "drop"
    for u in data.get("uncertain", []):
        seen.setdefault(u.get("id"), "uncertain")
    missing = ids - set(seen)
    if missing:
        return f"unassigned ids: {sorted(missing)}"
    return ""


# ------------------------------------------------------------- [C] ASSEMBLE

TELUGU_FRAG = re.compile(r"^[ఀ-౿]")  # starts with Telugu char (no opener)


def _is_continuation(prev_text: str, next_text: str) -> bool:
    if SENTENCE_FINAL.search(prev_text):
        return False
    if OPENER.match(next_text):
        return False
    return bool(TELUGU_FRAG.match(next_text.strip()))


def _stitch(parts: list[str]) -> list[str]:
    """Merge mid-sentence fragments into paragraphs."""
    out: list[str] = []
    for t in parts:
        t = t.strip()
        if not t:
            continue
        if out and _is_continuation(out[-1], t):
            out[-1] = out[-1].rstrip() + " " + t
        else:
            out.append(t)
    return out


def assemble(blocks: list[Block], data: dict) -> dict:
    by_id = {b.id: b for b in blocks}
    articles = []
    for art in data.get("articles", []):
        headline, subs, caps, tables = "", [], [], []
        body_entries = []
        for blk in art.get("blocks", []):
            b = by_id[blk["id"]]
            role = blk["role"]
            if role == "headline":
                headline = b.text
            elif role == "subheading":
                subs.append(b.text)
            elif role == "caption":
                caps.append(b.text or b.alt)
            elif role == "table":
                tables.append(b.text)
            elif role == "body":
                body_entries.append((blk.get("seq", 10**6), blk["id"], b.text))
        body_entries.sort()
        paragraphs = _stitch([t for _, _, t in body_entries])
        articles.append({
            "article_id": art["article_id"],
            "headline": headline,
            "subheadings": subs,
            "body_paragraphs": paragraphs,
            "captions": caps,
            "tables": tables,
            "bbox": art.get("bbox"),   # filled by optional geometry pass
            "block_ids": [blk["id"] for blk in art.get("blocks", [])],
        })
    return {
        "articles": articles,
        "dropped": data.get("drop", []),
        "uncertain": data.get("uncertain", []),
    }


# ------------------------------------------------------------------- MAIN

def run_sarvam_fullpage(pdf: Path) -> str:
    """Live Sarvam pass (output_format=html). Reuses the proven job flow."""
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]
                          / "backend" / "extraction"))
    from extract_articles import SarvamPipeline
    return SarvamPipeline().run(pdf)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--html", type=Path, help="cached Sarvam full-page HTML")
    ap.add_argument("--pdf", type=Path, help="source PDF (runs live Sarvam job)")
    ap.add_argument("--page-image", type=Path, help="page render for the vision model")
    ap.add_argument("--manifest", action="store_true", help="print block manifest and exit")
    ap.add_argument("--assignments", type=Path, help="manual assignment JSON (key-free mode)")
    ap.add_argument("--anthropic", action="store_true", help="use Claude API for assignment")
    ap.add_argument("--model", default="claude-opus-4-8")
    ap.add_argument("-o", "--out", type=Path, default=Path("articles.json"))
    args = ap.parse_args()

    if args.html:
        html = args.html.read_text(encoding="utf-8")
    elif args.pdf:
        html = run_sarvam_fullpage(args.pdf)
    else:
        ap.error("need --html or --pdf")

    blocks = parse_blocks(html)
    print(f"[A] atomized {len(blocks)} blocks", file=sys.stderr)

    if args.manifest:
        print(manifest(blocks))
        return

    if args.assignments:
        data = json.loads(args.assignments.read_text(encoding="utf-8"))
        err = check_assignment(blocks, data)
        if err:
            sys.exit(f"assignment file invalid: {err}")
    elif args.anthropic:
        if not args.page_image:
            ap.error("--anthropic requires --page-image")
        data = assign_with_anthropic(blocks, args.page_image, args.model)
    else:
        ap.error("need --assignments or --anthropic (or --manifest)")

    result = assemble(blocks, data)
    result["source"] = str(args.pdf or args.html)
    result["article_count"] = len(result["articles"])
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2),
                        encoding="utf-8")
    print(f"[C] wrote {result['article_count']} articles -> {args.out}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
