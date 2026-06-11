#!/usr/bin/env python3
"""
Stage [D] — deterministic validation (PLAN.md §4). No model calls.

Detects, per article:
  caption_leak   : AI image descriptions / figure-alt text inside body
  fused_articles : >1 dateline or >1 reporter signature in one body
  dateline_midbody : a dateline pattern appearing far from the body start
  flow_continuity: paragraph ends mid-sentence with no continuation
  headline_present
  order_sanity   : body blocks jump backwards in (row,col) without a declared
                   continuation (needs block geometry; new format only)

Works on BOTH the new structured output and the legacy flat output
(current_bad_output.json) — proving it catches the p1_a02 failure automatically.

Usage:  python validate.py articles.json [--html sarvam_fullpage.html]
Exit 0 = all pass; 1 = review flags; 2 = hard fail.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

AI_DESC = re.compile(r"ఈ చిత్రంలో|ఈ చిత్రం")
# dateline: "<place>, న్యూస్టుడే:"  or "న్యూస్టుడే, <place>:"  (OCR variants allowed)
DATELINE = re.compile(r"[ఀ-౿()\s]{2,30}[,:]\s*న్యూ[సన]్?\s?టుడే|న్యూ[సన]్?\s?టుడే\s*[,:]")
# reporter signature: "- న్యూస్టుడే, <place>"
SIGNATURE = re.compile(r"-\s*న్యూ[సన]్?\s?టుడే")
SENTENCE_FINAL = re.compile(r"[.?!।॥…'\"’”\)]\s*$")
# "- న్యూస్టుడే, జగిత్యాల"  or  "- రమ్యశ్రీ, శిక్షకులు"  (signature / attribution)
ATTRIBUTION_END = re.compile(r"-\s*[ఀ-౿][ఀ-౿\s,()]{2,40}$")


def _bodies(article: dict) -> list[str]:
    if "body_paragraphs" in article:
        return [p for p in article["body_paragraphs"] if p.strip()]
    body = article.get("body", "")
    return [body] if body.strip() else []


def check_article(article: dict) -> list[str]:
    flags = []
    paras = _bodies(article)
    body = "\n".join(paras)

    if AI_DESC.search(body):
        flags.append("caption_leak: AI image description inside body")

    datelines = DATELINE.findall(body)
    signatures = SIGNATURE.findall(body)
    if len(datelines) + len(signatures) > 2 or len(datelines) > 1:
        flags.append(f"fused_articles: {len(datelines)} datelines + "
                     f"{len(signatures)} signatures in one body")
    else:
        for m in DATELINE.finditer(body):
            # signatures ("- న్యూస్టుడే, …") are endings, not new datelines
            if body[max(0, m.start() - 3):m.start()].strip().endswith("-"):
                continue
            if m.start() > max(200, len(body) * 0.3):
                flags.append(f"dateline_midbody: dateline at offset {m.start()}")
            break

    if not (article.get("headline") or "").strip():
        flags.append("headline_missing")

    def ends_ok(p: str) -> bool:
        return bool(SENTENCE_FINAL.search(p) or ATTRIBUTION_END.search(p))

    if paras and not ends_ok(paras[-1]):
        flags.append("flow_continuity: article ends mid-sentence")
    for i, p in enumerate(paras[:-1]):
        # a paragraph that ends mid-sentence should have been stitched;
        # if it survives as a separate paragraph the order is suspect
        if len(p) > 60 and not ends_ok(p):
            flags.append(f"flow_continuity: paragraph {i + 1} ends mid-sentence")
    return flags


def check_order(article: dict, blocks_geo: dict[int, tuple[int, int]],
                blocks_text: dict[int, str],
                assignment: dict[int, dict]) -> list[str]:
    """A backwards (row,col) jump is only suspicious when the text flow was
    broken — i.e. the previous block ended mid-sentence yet the next body
    block sits earlier on the page without a declared continuation."""
    flags = []
    ids = [b for b in article.get("block_ids", []) if b in blocks_geo
           and assignment.get(b, {}).get("role") == "body"]
    ids.sort(key=lambda i: assignment[i].get("seq", 0))
    prev = None
    for i in ids:
        if (prev is not None and blocks_geo[i] < blocks_geo[prev]
                and not assignment[i].get("continues_block")
                and not SENTENCE_FINAL.search(blocks_text.get(prev, "."))):
            flags.append(f"order_sanity: block {i} {blocks_geo[i]} follows "
                         f"unfinished block {prev} {blocks_geo[prev]} "
                         f"without continues_block")
        prev = i
    return flags


def check_coverage(result: dict, blocks) -> list[str]:
    assigned = set()
    for a in result.get("articles", []):
        for i in a.get("block_ids", []):
            if i in assigned:
                return [f"coverage: block {i} assigned twice (HARD FAIL)"]
            assigned.add(i)
    for d in result.get("dropped", []):
        assigned.add(d["id"])
    for u in result.get("uncertain", []):
        assigned.add(u["id"])
    text_ids = {b.id for b in blocks if b.cls in
                ("paragraph", "headline", "section-title", "footnote",
                 "advertisement", "table")}
    missing = text_ids - assigned
    return [f"coverage: text blocks never assigned: {sorted(missing)}"] if missing else []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("articles", type=Path)
    ap.add_argument("--html", type=Path, help="source HTML for coverage/order checks")
    ap.add_argument("--assignments", type=Path, help="assignment JSON for order checks")
    args = ap.parse_args()

    result = json.loads(args.articles.read_text(encoding="utf-8"))
    arts = result.get("articles", [])

    blocks, geo, texts, assign_by_id = None, {}, {}, {}
    if args.html:
        sys.path.insert(0, str(Path(__file__).parent))
        from pipeline import parse_blocks
        blocks = parse_blocks(args.html.read_text(encoding="utf-8"))
        geo = {b.id: (b.row, b.col) for b in blocks}
        texts = {b.id: b.text for b in blocks}
    if args.assignments:
        adata = json.loads(args.assignments.read_text(encoding="utf-8"))
        for art in adata.get("articles", []):
            for blk in art.get("blocks", []):
                assign_by_id[blk["id"]] = blk

    hard_fail = False
    total_flags = 0
    for a in arts:
        flags = check_article(a)
        if geo and assign_by_id and "block_ids" in a:
            flags += check_order(a, geo, texts, assign_by_id)
        if flags:
            total_flags += len(flags)
            hl = (a.get("headline") or "(no headline)")[:40]
            print(f"REVIEW  {a.get('article_id', '?'):24s} {hl}")
            for f in flags:
                print(f"        - {f}")
                if "HARD FAIL" in f:
                    hard_fail = True
        else:
            print(f"PASS    {a.get('article_id', '?'):24s} "
                  f"{(a.get('headline') or '')[:40]}")

    if blocks is not None:
        for f in check_coverage(result, blocks):
            print(f"PAGE    - {f}")
            total_flags += 1
            if "HARD FAIL" in f:
                hard_fail = True
    for u in result.get("uncertain", []):
        print(f"PAGE    - uncertain block {u['id']}: {u.get('reason', '')[:70]}")

    n = len(arts)
    print(f"\nVERDICT: {n} articles, {total_flags} flags, "
          f"{len(result.get('uncertain', []))} uncertain"
          + (" — HARD FAIL" if hard_fail else ""))
    sys.exit(2 if hard_fail else (1 if total_flags else 0))


if __name__ == "__main__":
    main()
