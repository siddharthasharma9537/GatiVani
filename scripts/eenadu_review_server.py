"""Local-only server for the Eenadu review screen (personal use, owner's Mac).

Serves the Flutter web build (built with --dart-define=EENADU_REVIEW=true) and a
small JSON API over the owner's local files. Nothing is uploaded anywhere and
no Eenadu content is stored in this repository.

Run it with the Python that has PyMuPDF (the Veda venv):

    ~/eenadu-env/bin/python scripts/eenadu_review_server.py

It binds to the LAN so a phone on the same Wi-Fi can open it. A random access
key is generated on every start and printed in the URL; requests to the API
without it are refused. The connection is plain HTTP, so use it on a network
you trust.

API (all under /review-api/, key required):
  GET  editions                       -> [{edition, date, pages}]
  GET  page?edition=&date=&page=      -> {width, height, blocks:[{id, box, kind, lines:[{converted, old, ocr, fonts}]}], articles:[{headline, blockIds, graphicBox?}]}
  GET  image?edition=&date=&page=     -> JPEG of the page
  GET  crop?edition=&date=&page=&box=x0,y0,x1,y1  -> JPEG of one block (box in fractions of the page)
  GET  results?edition=&date=         -> {blockId: {verdict, note}}
  PUT  results?edition=&date=         -> same shape, replaces the file
"""
import argparse
import collections
import difflib
import glob
import http.server
import json
import os
import re
import secrets
import socket
import sys
import tempfile
import threading
import urllib.parse

import pymupdf

BODY_FONT = "Eenadu-Light"  # the font the old statistical table covered (kept for the comparison line)
IMG_ZOOM = 1.4
CROP_ZOOM = 2.2   # crops are shown at phone width, so they are cut sharper than the page image


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


class Store:
    def __init__(self, drive, font_dir, glyph_dir, state_dir):
        self.drive, self.font_dir, self.state_dir = drive, font_dir, state_dir
        os.makedirs(os.path.join(state_dir, "images"), exist_ok=True)
        with open(os.path.join(font_dir, "table_v2.json"), encoding="utf-8") as f:
            self.table = json.load(f)            # the old statistical table, kept for comparison
        # The direct glyph reading (rules.py + table3.json) lives with the owner's other Eenadu files, not in this repo.
        sys.path.insert(0, glyph_dir)
        import fonts
        self.fonts = fonts
        self.glyph_dir = glyph_dir
        self._lock = threading.RLock()     # PyMuPDF documents are not thread-safe; the HTTP server is threaded
        self._ocr_cache = {}
        self._paper_cache = {}
        self._page_cache = {}
        self._lex = None
        self.rejoin_log = {"joined": 0, "unclear": []}
        self.reflow_log = {}
        self.opt_tags = True
        self.opt_reflow = True
        self.join_log = {"kept_jump_headings": [], "sentences_rejoined": 0}
        self._docs = {}

    def editions(self):
        out = []
        for mf in sorted(glob.glob(os.path.join(self.drive, "manifest-*.json"))):
            with open(mf, encoding="utf-8") as f:
                m = json.load(f)
            for name, e in m.get("editions", {}).items():
                if e.get("status") == "ok" and os.path.exists(os.path.join(self.drive, e["pdf"])):
                    out.append({"edition": name, "date": m["date"], "pages": e["pages"]})
        return out

    def _pdf_path(self, edition, date):
        # Only paths named in a manifest are ever opened (no user-built paths).
        for e in self.editions():
            if e["edition"] == edition and e["date"] == date:
                return os.path.join(self.drive, "Eenadu_%s_%s.pdf" % (edition, date)), e["pages"]
        return None, 0

    def doc(self, edition, date):
        path, _ = self._pdf_path(edition, date)
        if path is None:
            return None
        if path not in self._docs:
            self._docs[path] = pymupdf.open(path)
        return self._docs[path]

    def _decode_old(self, codes):
        return "".join(self.table.get(c, ["?"])[0] if c != " " else " " for c in codes)

    # Eenadu's own page names -> the section tag GatiVani shows. Pages called just "Page" get no tag (general news):
    # what the unlabelled pages are is not guessed.
    SECTION_BY_LABEL = {"EDITORIAL": "Editorial", "FRONT PAGE": "Front page", "BACK PAGE": "Back page", "BUSINESS": "Business",
                        "CINEMA": "Entertainment", "VASUNDHARA": "Vasundhara", "CHAMPION": "Champion", "PRATIBHA": "Pratibha",
                        "CHADUVU": "Chaduvu", "REGIONAL": "Regional", "NATIONAL": "National"}

    def _page_label(self, edition, date, pno):
        """The page's printed label (NewsProPageTitle). From the links.json the daily link step writes ('pages': [{page, title}]);
        until that exists for a day, from page_labels_<date>.json next to the converter."""
        labels = None
        lj = os.path.join(self.drive, "Eenadu_%s_%s.links.json" % (edition, date))
        if os.path.exists(lj):
            try:
                pages = json.load(open(lj, encoding="utf-8")).get("pages")
                if pages:
                    labels = {int(p["page"]): p.get("title", "") for p in pages}
            except (ValueError, KeyError):
                labels = None
        if labels is None:
            fb = os.path.join(self.glyph_dir, "page_labels_%s.json" % date)
            if os.path.exists(fb):
                labels = {int(k): v for k, v in json.load(open(fb, encoding="utf-8")).get(edition, {}).items()}
        label = (labels or {}).get(pno, "")
        if label.strip().lower() == "page":
            label = ""
        key = re.sub(r"-\d+$", "", label.upper())
        return label, self.SECTION_BY_LABEL.get(key, "")

    def _line_ocr(self, edition, pno):
        """Tesseract readings of whole lines, from lines_<ED>.json next to the converter (made by lineocr.py)."""
        code = {"TELANGANA": "TG", "ANDHRA-PRADESH": "AP", "GREATER-HYDERABAD": "GH"}.get(edition)
        if code not in self._ocr_cache:
            path = os.path.join(self.glyph_dir, "lines_%s.json" % code)
            rows = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else []
            by = {}
            for r in rows:
                by[(r["page"], tuple(round(v, 1) for v in r["bbox"]))] = re.sub("[\u200b\u200c\u200d]", "", r["ocr"])
            self._ocr_cache[code] = by
        return {k[1]: v for k, v in self._ocr_cache[code].items() if k[0] == pno}

    def page(self, edition, date, pno):
        with self._lock:
            key = (edition, date, pno)
            if key not in self._page_cache:
                self._page_cache[key] = self._page_uncached(edition, date, pno)
            return self._page_cache[key]

    def _page_uncached(self, edition, date, pno):
        doc = self.doc(edition, date)
        if doc is None or not 1 <= pno <= len(doc):
            return None
        pg = doc[pno - 1]
        W, H = pg.rect.width, pg.rect.height
        ocr = self._line_ocr(edition, pno)
        blocks = []
        for bi, b in enumerate(pg.get_text("rawdict")["blocks"]):
            lines, x0, y0, x1, y1 = [], 1e9, 1e9, 0, 0
            n_head = 0
            for l in b.get("lines", []):
                spans = [(s["font"].split("+")[-1], "".join(ch["c"] for ch in s["chars"]), s) for s in l["spans"]]
                spans = [t for t in spans if t[1].strip()]
                if not spans or sum(len(t[1].strip()) for t in spans) < 3:
                    continue
                if not any(self.fonts.table_for(f) is not None for f, _, _ in spans):
                    continue                      # a line of pure Latin/symbol text is not what is being reviewed
                n_head += any(self._is_headline(f, s["size"]) for f, _, s in spans)
                bb = l["bbox"]
                x0, y0, x1, y1 = min(x0, bb[0]), min(y0, bb[1]), max(x1, bb[2]), max(y1, bb[3])
                line_ocr = ocr.get(tuple(round(v, 1) for v in bb))
                lines.append({
                    "converted": self.fonts.decode_line([(f, c) for f, c, _ in spans]),
                    "old": self._decode_old("".join(c for f, c, _ in spans if f == BODY_FONT)) if all(f == BODY_FONT for f, _, _ in spans) else None,
                    "ocr": line_ocr,
                    "fonts": sorted({f for f, _, _ in spans}),
                    # geometry and type for sorting a story into headline / byline / subheading / caption / paragraphs
                    "bbox": [round(v, 1) for v in bb],
                    "size": round(max(s["size"] for f, _, s in spans if self.fonts.table_for(f) is not None), 1),
                    "bold": any(s["flags"] & 16 for f, _, s in spans if self.fonts.table_for(f) is not None),
                    "bullet": any(f in self.fonts.SYMBOL_FONTS for f, _, _ in spans),
                    "tfonts": sorted({f for f, _, _ in spans if self.fonts.table_for(f) is not None}),
                })
            if lines:
                # a headline block is one that is mostly headline-size lines; a body block with a heading inside keeps its text
                headline = n_head >= 0.6 * len(lines)
                has_ocr = all(l["ocr"] is not None for l in lines)
                differs = any(self._differs(l["converted"], l["ocr"]) for l in lines if l["ocr"] is not None)
                blocks.append({"id": "%d:%d" % (pno, bi), "box": [x0 / W, y0 / H, x1 / W, y1 / H], "lines": lines,
                               "kind": "headline" if headline else "body", "hasOcr": has_ocr,
                               # worth a human look: every headline, any block whose reading differs from the OCR, any block
                               # with no OCR to compare against
                               "needsLook": headline or differs or not has_ocr})
        self._mark_boxed(pg, blocks, W, H)
        label, section = self._page_label(edition, date, pno)
        return {"width": W, "height": H, "blocks": blocks, "articles": self._articles(blocks, self._wide_pictures(pg)),
                "label": label, "section": section}

    @staticmethod
    def _differs(a, b):
        norm = lambda t: re.sub(r"[\s.,;:!?'\"\u201c\u201d\u2018\u2019()\-_/|\u0964\u0965\u200b\u200c\u200d]", "", t)
        x, y = norm(a), norm(b)
        return x != y and difflib.SequenceMatcher(None, x, y).ratio() < 0.9

    @staticmethod
    def _is_headline(font, size):
        # first cut: large type in the heading faces
        return (font == "Narmada" and size >= 18) or (font in ("GodawariHeading", "GodawariSubHeading") and size >= 16) \
            or (font == "Tapati" and size >= 18)

    @staticmethod
    def _mark_boxed(pg, blocks, W, H):
        """Flag blocks that sit inside a tinted or bordered box drawn on the page (a sidebar / boxed note), rather than in the
        plain column. Boxes are small rectangles (under 25% of the page, over 3 text lines)."""
        rects = []
        for d in pg.get_drawings():
            r = d["rect"]
            area = r.width * r.height
            if area > 0.25 * W * H or r.width < 60 or r.height < 40:
                continue
            fill = d.get("fill")
            tinted = fill is not None and tuple(fill) != (1.0, 1.0, 1.0)
            bordered = d.get("color") is not None and (d.get("width") or 0) > 0 and d.get("fill") is None
            if tinted or bordered:
                rects.append(r)
        for b in blocks:
            x0, y0, x1, y1 = b["box"][0] * W, b["box"][1] * H, b["box"][2] * W, b["box"][3] * H
            b["boxed"] = any(r.x0 - 3 <= x0 and r.y0 - 3 <= y0 and x1 <= r.x1 + 3 and y1 <= r.y1 + 3 for r in rects)

    @staticmethod
    def _wide_pictures(pg):
        """Wide, short pictures on the page (fractions of the page): big display headlines are often printed as a picture, with
        no text in the PDF at all. Photos are mostly squarer, the masthead sits at the very top; both are left out."""
        W, H = pg.rect.width, pg.rect.height
        out = []
        for im in pg.get_image_info():
            x0, y0, x1, y1 = im["bbox"]
            w, h = x1 - x0, y1 - y0
            if h > 0 and w / h >= 2.5 and w >= 0.15 * W and h >= 0.015 * H and y0 > 0.08 * H:
                out.append([x0 / W, y0 / H, x1 / W, y1 / H])
        return out

    @staticmethod
    def _articles(blocks, pictures=()):
        """FIRST CUT grouping: a headline block starts an article; the body blocks that follow, in the PDF's own order,
        belong to it until the next headline. Blocks before the first headline are grouped as 'page furniture'.
        If a wide picture sits right above the group, its headline is probably that picture ('graphicBox'): needs OCR."""
        # Each headline block starts a group. A body block joins the group whose headline sits closest ABOVE it with a horizontal overlap
        # (a story's text normally lies under its headline); when none fits, it follows the previous block in the PDF's own order.
        arts, idx_of = [], {}
        for i, b in enumerate(blocks):
            if b["kind"] == "headline":
                arts.append({"headline": " ".join(l["converted"] for l in b["lines"]), "blockIds": [b["id"]], "_boxes": [b["box"]],
                             "_idx": [i], "_hb": b["box"]})
        cur = None
        for i, b in enumerate(blocks):
            if b["kind"] == "headline":
                cur = next(a for a in arts if a["_idx"][0] == i)
                continue
            bx = b["box"]
            best, bgap = None, 1e9
            for a in arts:
                hb = a["_hb"]
                gap = bx[1] - hb[3]
                ov = min(bx[2], hb[2]) - max(bx[0], hb[0])
                if gap >= -0.02 and ov >= 0.5 * min(bx[2] - bx[0], hb[2] - hb[0]) and gap < bgap:
                    best, bgap = a, gap
            if best is None:
                best = cur
            if best is None:                       # text before any headline: page furniture
                best = {"headline": "", "blockIds": [], "_boxes": [], "_idx": [], "_hb": [0, 0, 0, 0]}
                arts.insert(0, best)
            best["blockIds"].append(b["id"])
            best["_boxes"].append(bx)
            best["_idx"].append(i)
        order = {b["id"]: i for i, b in enumerate(blocks)}
        for a in arts:
            a["blockIds"].sort(key=lambda bid: order[bid])
            a.pop("_idx", None)
            a.pop("_hb", None)
        for a in arts:
            boxes = a.pop("_boxes")
            gx0, gy0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
            gx1 = max(b[2] for b in boxes)
            for p in pictures:
                gap = gy0 - p[3]
                overlap = min(gx1, p[2]) - max(gx0, p[0])
                if -0.04 <= gap <= 0.02 and overlap >= 0.5 * min(gx1 - gx0, p[2] - p[0]):
                    a["graphicBox"] = p
                    break
        return arts

    # ── The paper as news: stories grouped by Eenadu's own page labels (for the app's "Today's paper" screen) ──────────────────────
    SECTION_ORDER = ["Front page", "Editorial", "Business", "Entertainment", "Champion", "Vasundhara", "Pratibha", "Chaduvu",
                     "Regional", "National", "Back page", "News"]
    SECTION_TITLE = {"Editorial": "Editorial news", "Entertainment": "Cinema", "Champion": "Champion (sports)", "News": "General news"}
    # "(మిగతా 2లో)" with or without the brackets, possibly several in a row
    _POINTER = re.compile(r"\(?\s*\u0c2e\u0c3f\u0c17\u0c24\u0c3e\s*\d{1,2}\s*\u0c32\u0c4b\s*\)?")
    _CONT_MARK = re.compile(r"\u0c2e\u0c3f\u0c17\u0c24\u0c3e\s*(\d{1,2})\s*\u0c32\u0c4b")      # "మిగతా N లో": continued on page N
    _CONT_HEAD = "\u0c24\u0c30\u0c41\u0c35\u0c3e\u0c2f\u0c3f"                                       # "తరువాయి": continued from

    def paper(self, edition, date):
        key = (edition, date)
        with self._lock:
            if key not in self._paper_cache:
                self._paper_cache[key] = self._build_paper(edition, date)
            return self._paper_cache[key]

    # ── Sorting a story's text into roles ──────────────────────────────────────────────────────────────────────────────────
    DISPLAY_FONTS = {"Narmada", "GodawariHeading", "GodawariSubHeading", "Tapati"}
    _MARK_TO = re.compile(r"^[\s.\u2026]*\u0c2e\u0c3f\u0c17\u0c24\u0c3e\s*\d{1,2}\s*\u0c32\u0c4b[\s.]*$")      # whole line "...మిగతా N లో"
    _MARK_TO_END = re.compile(r"[\s.\u2026]*\u0c2e\u0c3f\u0c17\u0c24\u0c3e\s*(\d{1,2})\s*\u0c32\u0c4b[\s.]*$")      # the same at a line's end
    # "ఈనాడు, హైదరాబాద్:" / "న్యూస్‌టుడే, కరీంనగర్" at the start of a story
    _DATELINE = re.compile(r"^\s*[\u2022\-\u2013]?\s*(\u0c08\u0c28\u0c3e\u0c21\u0c41|\u0c28\u0c4d\u0c2f\u0c42\u0c38\u0c4d[\u200c]?\u0c1f\u0c41\u0c21\u0c47)[^:\n]{0,40}:\s*")
    _CREDIT = re.compile(r"^\s*[\u2022\-\u2013]\s*(\u0c08\u0c28\u0c3e\u0c21\u0c41|\u0c28\u0c4d\u0c2f\u0c42\u0c38\u0c4d[\u200c]?\u0c1f\u0c41\u0c21\u0c47)")

    def _lexicon(self):
        """Words and word pairs that appear INSIDE printed lines (not first or last on a line, where a word may be cut), over all
        three editions: the corpus used to decide whether two pieces across a line break are one word."""
        if self._lex is None:
            words, pairs = collections.Counter(), collections.Counter()
            for ed, date in sorted({(e["edition"], e["date"]) for e in self.editions()}):
                doc = self.doc(ed, date)
                for pno in range(1, len(doc) + 1):
                    for b in self.page(ed, date, pno)["blocks"]:
                        for l in b["lines"]:
                            toks = [self._word(t) for t in l["converted"].split()]
                            for i in range(1, len(toks) - 1):
                                words[toks[i]] += 1
                                if i + 1 < len(toks) - 1:
                                    pairs[(toks[i], toks[i + 1])] += 1
            self._lex = (words, pairs)
        return self._lex

    _TELWORD = re.compile("^[\u0c00-\u0c7f]+$")

    @staticmethod
    def _word(t):
        return t.strip(".,;:!?()[]{}'\"\u2018\u2019\u201c\u201d\u2026\u2022-\u0964\u0965")

    def _join_lines(self, lines):
        """Join printed lines into running text. A space goes between lines, except where the line end cuts a word: the two
        pieces are glued only when the joined word is attested and at least one piece is not independently attested.
        Ambiguous boundaries are logged instead of guessing."""
        words, pairs = self._lexicon()
        out = lines[0].strip()
        for nxt in lines[1:]:
            nxt = nxt.strip()
            ta, tb = out.split(" ")[-1] if out else "", nxt.split(" ")[0] if nxt else ""
            # Keep punctuation in the output; only quotes on the outside of the boundary may be ignored.
            a, b = ta.lstrip("'\"\u2018\u201c\u2022"), tb.rstrip(".,;:!?)]}'\"\u2019\u201d\u2026\u0964\u0965")
            if a and b and self._TELWORD.fullmatch(a) and self._TELWORD.fullmatch(b):
                fj, separate = words.get(a + b, 0), pairs.get((a, b), 0)
                if fj and not separate and (not words.get(a, 0) or not words.get(b, 0)):
                    out += nxt
                    self.rejoin_log["joined"] += 1
                    continue
                if fj or not words.get(a, 0) or not words.get(b, 0):
                    self.rejoin_log["unclear"].append((a, b, fj, separate))
            out += " " + nxt
        return out

    _TAG_END = re.compile(r"\s*(\d{1,2})\s*\u0c32\u0c4b\s*$")        # the printed jump badge "3లో" at the end of a headline/deck line

    def _line_role(self, l):
        txt = l["converted"].strip()
        if not txt:
            return None
        fonts = set(l["tfonts"])
        display = bool(fonts) and fonts <= self.DISPLAY_FONTS
        size = l["size"]
        if self._CONT_HEAD in txt and len(txt) < 48:
            return "marker_from"
        if self._MARK_TO.match(txt):
            return "marker_to"
        if display and re.match(r"^\s*[-\u2013]\s*\S", txt) and len(txt) < 45 and size <= 20:
            return "byline"                      # an author's name set under an opinion piece: "- జమ్నాలాల్ బజాజ్"
        if any(self._is_headline(f, size) for f in fonts):
            return "headline"
        if display and size < 13.15:
            return "caption"
        if l["bullet"] and display:
            return "deck"
        if display and size >= 14.4:
            return "subhead"
        return "body"

    def _structure(self, blocks, big_box_ok=True):
        """A story's blocks -> ordered items {role, text}. Roles: deck, byline, subhead, body, caption, sidebar, marker."""
        items = []
        tags = []
        boxed_words = sum(len(" ".join(l["converted"] for l in b["lines"]).split()) for b in blocks if b.get("boxed") and b["kind"] != "headline")
        all_words = sum(len(" ".join(l["converted"] for l in b["lines"]).split()) for b in blocks if b["kind"] != "headline") or 1
        # when most of a story sits in a box the box is its background, not a sidebar
        sidebars_on = big_box_ok and boxed_words < 0.6 * all_words
        prevl = None
        subhead_size = 0
        subhead_count = 0
        sidebar = False
        for b in blocks:
            if b["kind"] == "headline":
                continue
            run, runrole = [], None

            def flush():
                nonlocal run, runrole
                if not run:
                    return
                if runrole == "body":
                    # Paragraph starts: a line indented a little from its column's left edge, or a larger gap above it. A line far to the
                    # right or left of the running column edge starts the next column: the text goes on, no paragraph break.
                    hts = sorted(l["bbox"][3] - l["bbox"][1] for l in run)
                    lh = hts[len(hts) // 2] or 10
                    colleft = run[0]["bbox"][0]
                    paras, cur = [], [run[0]]
                    for prev, l in zip(run, run[1:]):
                        dx = l["bbox"][0] - colleft
                        newcol = abs(dx) > 15 or l["bbox"][1] < prev["bbox"][1] - 2 * lh
                        if newcol:
                            colleft = l["bbox"][0]
                        elif dx > 3 or l["bbox"][1] - prev["bbox"][3] > 0.5 * lh:
                            paras.append(cur)
                            cur = []
                        cur.append(l)
                    paras.append(cur)
                    # does the first paragraph of this block start a paragraph, or go on from the block before (the next column)?
                    left_all = min(l["bbox"][0] for l in run)
                    first_indented = len(run) > 1 and run[0]["bbox"][0] - left_all > 3
                    for k, ps in enumerate(paras):
                        role = "sidebar" if sidebar or (sidebars_on and b.get("boxed")) else "body"
                        text = self._join_lines([l["converted"] for l in ps])
                        if k == 0 and not first_indented and items and items[-1]["role"] == role and items[-1].get("_open"):
                            items[-1]["text"] = self._join_lines([items[-1]["text"], text])
                        else:
                            items.append({"role": role, "text": text})
                        items[-1]["_open"] = (k == len(paras) - 1)
                    run, runrole = [], None
                    return
                elif runrole == "caption":
                    cur = []
                    for l in run:
                        if l["bullet"] and cur:
                            items.append({"role": "caption", "text": self._join_lines([x["converted"] for x in cur])})
                            cur = []
                        cur.append(l)
                    items.append({"role": "caption", "text": self._join_lines([x["converted"] for x in cur])})
                elif runrole == "deck":
                    cur = []
                    for l in run:
                        if l["bullet"] and cur:
                            items.append({"role": "deck", "text": self._join_lines([x["converted"] for x in cur])})
                            cur = []
                        cur.append(l)
                    items.append({"role": "deck", "text": self._join_lines([x["converted"] for x in cur])})
                else:
                    items.append({"role": runrole, "text": self._join_lines([l["converted"] for l in run])})
                run, runrole = [], None

            for l in b["lines"]:
                # a short display line that ends with the jump badge "3లో": the badge is a pointer, not text
                m = self._TAG_END.search(l["converted"])
                if self.opt_tags and re.fullmatch(r"[\s\u200b\u200c\u200d]*\d{1,2}[\s\u200b\u200c\u200d]*\u0c32\u0c4b[\s\u200b\u200c\u200d]*", l["converted"]):
                    tags.append(int(re.search(r"\d+", l["converted"]).group(0)))      # a line that is only the badge "3లో"
                    continue
                if self.opt_tags and m and len(l["converted"]) < 90 and "\u0c2e\u0c3f\u0c17\u0c24\u0c3e" not in l["converted"] \
                        and set(l["tfonts"]) <= self.DISPLAY_FONTS | {"Eenadu-Light"} and l["converted"][:m.start()].strip():
                    tags.append(int(m.group(1)))
                    l = dict(l, converted=l["converted"][:m.start()])
                role = self._line_role(l)
                if role is None:
                    continue
                if role == "headline":
                    role = "subhead"
                # A smaller display heading after the main subheads introduces a side note.
                # Keep its following columns together, but exclude them from narration.
                if role == "body" and subhead_count >= 2 and l is b["lines"][-1] \
                        and set(l["tfonts"]) <= self.DISPLAY_FONTS and 13.15 <= l["size"] < subhead_size - 0.6:
                    flush()
                    sidebar = True
                    items.append({"role": "sidebar", "text": l["converted"].strip()})
                    continue
                if role == "subhead":
                    if runrole != "subhead":
                        subhead_count += 1
                    if sidebar:
                        flush()
                    subhead_size = max(subhead_size, l["size"])
                    sidebar = False
                if role == "subhead" and (runrole == "deck" or (not run and items and items[-1]["role"] == "deck")) \
                        and prevl is not None and abs(prevl["size"] - l["size"]) < 0.6 and l["bbox"][1] - prevl["bbox"][3] < 8:
                    role = "deck"
                prevl = l
                if role == "marker_to":
                    flush()
                    items.append({"role": "marker", "text": "continues on page %s" % re.search(r"\d+", l["converted"]).group(0)})
                    continue
                if role == "byline":
                    flush()
                    items.append({"role": "byline", "text": l["converted"].strip("-\u2013 ").strip()})
                    continue
                if role == "marker_from":
                    flush()
                    items.append({"role": "marker", "text": "continued from page 1" if "\u0c2e\u0c4a\u0c26\u0c1f\u0c3f" in l["converted"] else l["converted"].strip("() ")})
                    continue
                if role == "body":
                    m = self._MARK_TO_END.search(l["converted"])
                    if m and len(l["converted"]) > len(m.group(0)):
                        # a body line that ends with "...మిగతా N లో": keep the text, show the marker apart
                        l = dict(l, converted=l["converted"][:m.start()])
                        flush_marker = m.group(1)
                    else:
                        flush_marker = None
                else:
                    flush_marker = None
                if role != runrole:
                    flush()
                    runrole = role
                run.append(l)
                if flush_marker:
                    flush()
                    items.append({"role": "marker", "text": "continues on page %s" % flush_marker})
            flush()
        merged = []
        for it in items:
            it.pop("_open", None)
            if it["role"] == "sidebar" and merged and merged[-1]["role"] == "sidebar":
                merged[-1]["text"] += "\n\n" + it["text"]
            elif it["role"] == "deck" and not it["text"].lstrip().startswith("\u2022") and merged and merged[-1]["role"] == "deck":
                merged[-1]["text"] = self._join_lines([merged[-1]["text"], it["text"]])          # a deck bullet that runs over two lines
            elif it["role"] == "caption":
                starts_bullet = it["text"].lstrip().startswith("\u2022")
                for k, part in enumerate([t for t in re.split(r"(?=\u2022)", it["text"]) if t.strip()]):
                    part = part.strip("\u2022 ").strip()
                    if k == 0 and not starts_bullet and merged and merged[-1]["role"] == "caption":
                        merged[-1]["text"] = self._join_lines([merged[-1]["text"], part])    # the tail of the caption before it
                    else:
                        merged.append({"role": "caption", "text": part})
            else:
                merged.append(it)
        items = merged
        # a dateline or credit sits apart from the first / last sentence
        out = []
        for i, it in enumerate(items):
            if it["role"] == "body":
                m = self._DATELINE.match(it["text"])
                if m and not any(o["role"] == "byline" for o in out):
                    out.append({"role": "byline", "text": it["text"][:m.end()].strip(" :").strip("\u2022-\u2013 ").strip()})
                    rest = it["text"][m.end():].strip()
                    if rest:
                        out.append({"role": "body", "text": rest})
                    continue
                if self._CREDIT.match(it["text"]) and len(it["text"]) < 70:
                    out.append({"role": "byline", "text": it["text"].strip("\u2022-\u2013 ").strip()})
                    continue
            out.append(it)
        self._last_tags = tags
        return out

    @staticmethod
    def _clean_reading(t):
        t = Store._POINTER.sub(" ", t)
        t = re.sub(r"\([^()]*" + Store._CONT_HEAD + r"[^()]*\)", " ", t)
        return re.sub(r"[ \t]{2,}", " ", t).strip()

    @staticmethod
    def _narration(st):
        """What would be read aloud: the headline once, then the body paragraphs and subheadings in order. No page markers, captions,
        boxed notes, deck bullets, bylines or repeated headings."""
        def clean(t):
            t = Store._clean_reading(t)
            t = re.sub(r"\s{2,}", " ", t).strip()
            # a paragraph that ends in a bare "3లో" (no full stop before it) ends in the printed jump badge
            return re.sub(r"(?<=[^\s.\u0964?!\u2026])\s+\d{1,2}\s*\u0c32\u0c4b$", "", t).strip()

        badge = re.compile(r"[\s\u200b\u200c\u200d]*\d{1,2}[\s\u200b\u200c\u200d]*\u0c32\u0c4b[\s\u200b\u200c\u200d]*")
        head = clean(st["headline"])
        parts = [head] if head and not badge.fullmatch(head) else []
        for it in st["items"]:
            if it["role"] in ("body", "subhead") and it["text"].strip():
                text = clean(it["text"])
                if badge.fullmatch(text):
                    continue                                   # a paragraph that is only the badge "3లో"
                if not text or (parts and text == parts[-1]):
                    continue                                   # never the same heading twice in a row
                parts.append(text)
        return "\n\n".join(parts)

    def _reflow(self, p):
        """Groups for one page, with text that flows from one column into the next put back with its story. A body block whose first
        line starts in the middle of a word that the block to its left leaves unfinished (కేసు | లను = కేసులను) is the next column of
        that block's story, even when it sits under a different headline. Returns (groups, number of blocks moved)."""
        words, pairs = self._lexicon()
        groups = [dict(a, blockIds=list(a["blockIds"])) for a in p["articles"]]
        byid = {b["id"]: b for b in p["blocks"]}
        owner = {i: g for g in groups for i in g["blockIds"]}
        moved = 0
        for b in p["blocks"]:
            if b["kind"] == "headline" or not b["lines"]:
                continue
            tb = b["lines"][0]["converted"].split()[0] if b["lines"][0]["converted"].split() else ""
            if not tb or not self._TELWORD.match(tb):
                continue
            x0, y0 = b["box"][0], b["box"][1]
            best, bd = None, 1e9
            for q in p["blocks"]:
                if q is b or q["kind"] == "headline" or not q["lines"]:
                    continue
                qx1, qy1 = q["box"][2], q["box"][3]
                if not (x0 - 0.20 <= qx1 <= x0 + 0.03 and qy1 >= y0):
                    continue
                last = q["lines"][-1]["converted"].strip()
                if re.search(r"[.?!\u2026\u0964'\"\u2019\u201d)]\s*$", last):
                    continue                                   # the left block ends a sentence: nothing flows on
                ta = last.split(" ")[-1]
                fj = words.get(ta + tb, 0) if self._TELWORD.match(ta) else 0
                if fj >= 1 and pairs.get((ta, tb), 0) == 0 and (fj >= 2 or words.get(tb, 0) < 2):
                    d = x0 - qx1
                    if abs(d) < bd:
                        best, bd = q, abs(d)
            if best is not None and owner.get(b["id"]) is not owner.get(best["id"]):
                src, dst = owner[b["id"]], owner[best["id"]]
                src["blockIds"].remove(b["id"])
                dst["blockIds"].append(b["id"])
                owner[b["id"]] = dst
                moved += 1
        order = {b["id"]: i for i, b in enumerate(p["blocks"])}
        for g in groups:
            g["blockIds"].sort(key=lambda bid: order[bid])
        self.reflow_log.setdefault("moved", []).append((p.get("label", ""), moved))
        return groups, moved

    def _build_paper(self, edition, date):
        doc = self.doc(edition, date)
        if doc is None:
            return None
        stories = []
        for pno in range(1, len(doc) + 1):
            p = self.page(edition, date, pno)
            byid = {b["id"]: b for b in p["blocks"]}
            groups, _moved = self._reflow(p) if self.opt_reflow else ([dict(a) for a in p["articles"]], 0)
            self.reflow_log.setdefault("by_page", {})[(edition, pno)] = _moved
            for gi, a in enumerate(groups):
                blocks = [byid[i] for i in a["blockIds"]]
                items = self._structure(blocks)
                paras = [it["text"] for it in items if it["role"] in ("body", "subhead", "deck", "sidebar") and it["text"]]
                words = sum(len(it["text"].split()) for it in items if it["role"] == "body")
                head = re.sub(r"[\u2022\u25cf\u25aa\u25a0]+", " ", a["headline"])
                head = re.sub(r"\s+", " ", head).strip()
                tags = list(getattr(self, "_last_tags", []))
                mt = self._TAG_END.search(head)
                if self.opt_tags and mt and head[:mt.start()].strip():
                    tags.append(int(mt.group(1)))              # the jump badge ("3లో") is a pointer, not headline text
                    head = head[:mt.start()].strip()
                graphic = a.get("graphicBox")
                if not head and not graphic and words < 40:
                    continue                     # page furniture and fragments
                first = " ".join(l["converted"] for b in blocks[:2] for l in b["lines"])
                bx = [byid[i]["box"] for i in a["blockIds"]]
                box = [min(b[0] for b in bx), min(b[1] for b in bx), max(b[2] for b in bx), max(b[3] for b in bx)]
                story = {"id": "p%d-g%d" % (pno, gi), "page": pno, "label": p["label"], "section": p["section"] or "News",
                         "headline": head, "graphic": graphic, "paras": paras, "items": items, "words": words, "box": box, "size": (p["width"], p["height"]),
                         "isCont": self._CONT_HEAD in first, "contTo": [], "contFrom": None, "hidden": False,
                         "headline_from": "", "kicker": "", "tags": tags}
                # a headline that runs over several blocks comes out as several head-only groups: join them to the story that follows
                prev = stories[-1] if stories else None
                if prev and prev["page"] == pno and prev["words"] == 0 and prev["headline"] and not prev["graphic"] and (head or paras) \
                        and not graphic and not any(it["role"] in ("deck", "byline", "subhead", "marker", "caption") for it in prev["items"]):
                    story["headline"] = (prev["headline"] + " " + head).strip()
                    story["box"] = [min(prev["box"][0], box[0]), min(prev["box"][1], box[1]), max(prev["box"][2], box[2]),
                                    max(prev["box"][3], box[3])]
                    stories.pop()
                stories.append(story)
        # Join front stories with their continuation. The jump list in links.json ("continued on page N" hotspots, in PDF points) says which
        # story on which page points where; the continuation on page N is the story that starts "(... తరువాయి)" and shares the most words.
        # A first cut: when nothing clear matches, the continuation is left unmatched and the story says so.
        def vocab(t):
            return {w for w in re.split(r"[\s.,;:!?'\"()\-]+", t) if len(w) >= 4}
        jumps = []
        lj = os.path.join(self.drive, "Eenadu_%s_%s.links.json" % (edition, date))
        if os.path.exists(lj):
            try:
                jumps = json.load(open(lj, encoding="utf-8")).get("jumps", [])
            except ValueError:
                jumps = []
        pairs = []                                   # (story, target page)
        for j in jumps:
            pg, to = int(j["page"]), int(j["to_page"])
            cx, cy = (j["rect"][0] + j["rect"][2]) / 2, (j["rect"][1] + j["rect"][3]) / 2
            best, bd = None, 1e18
            for st in stories:
                if st["page"] != pg:
                    continue
                W, H = st["size"]
                x0, y0, x1, y1 = st["box"][0] * W, st["box"][1] * H, st["box"][2] * W, st["box"][3] * H
                dx = max(x0 - cx, 0, cx - x1)
                dy = max(y0 - cy, 0, cy - y1)
                if dx * dx + dy * dy < bd:
                    best, bd = st, dx * dx + dy * dy
            if best is not None and bd <= 60 ** 2 and (best, to) not in pairs:
                pairs.append((best, to))
        for st in (stories if self.opt_tags else []):  # jump badges printed on the story ("3లో") are pointers too
            for n in st["tags"]:
                if all(not (x is st and y == n) for x, y in pairs):
                    pairs.append((st, n))
        if not jumps:                                # no links file: fall back to the "మిగతా N లో" words in the text
            for st in stories:
                for m in self._CONT_MARK.finditer(" ".join(st["paras"])):
                    pairs.append((st, int(m.group(1))))
        absorbed = {}                                # continuation story id -> the story it was joined into (for chains)
        for st, n in pairs:
            while st["id"] in absorbed:
                st = absorbed[st["id"]]
            text = " ".join(st["paras"])
            cands = [c for c in stories if c["page"] == n and c["isCont"] and not c["hidden"] and c is not st]
            best, score = None, 0
            head_words = vocab(st["headline"] + " " + text)
            for c in cands:
                # the continuation repeats the story's headline words; its first paragraphs share words with the front part
                sc = 3 * len(vocab(c["headline"]) & head_words) + len(vocab(" ".join(c["paras"][:4])) & vocab(text))
                if sc > score:
                    best, score = c, sc
            if best is None or score < 3:
                # no "(... తరువాయి)" block: a printed jump badge ("3లో") points at the full story, which repeats the headline
                sv = vocab(st["headline"])
                alt, asc = None, 0
                for c in stories:
                    if c["page"] == n and not c["hidden"] and c is not st and c["items"]:
                        k = len(vocab(c["headline"]) & sv)
                        if k > asc:
                            alt, asc = c, k
                if alt is not None and asc >= 3 and asc >= 0.5 * min(len(sv), len(vocab(alt["headline"])) or 1):
                    best, score = alt, 9
                    st["_by_headline"] = True
            if best is None or score < 3:
                reason = ("no continuation block marked '(... తరువాయి)' found on page %d" % n) if not cands else \
                    "%d candidate(s) on page %d, but none shares enough words with the front part (best score %d)" % (len(cands), n, score)
                st["contTo"].append({"page": n, "linked": False, "reason": reason})
                continue
            best["hidden"] = True
            best["contFrom"] = st["page"]
            absorbed[best["id"]] = st
            st["contTo"].append({"page": n, "linked": True})
            # ONE story: the continuation's body goes on as the next paragraphs. Page markers are dropped. The continuation's own
            # headline is dropped when it only repeats the story's headline / deck / words; a heading that does not look like a repeat
            # stays as a subheading and is listed in self.join_log["kept_jump_headings"].
            cont = [it for it in best["items"] if it["role"] != "marker"]
            front = [it for it in st["items"] if it["role"] != "marker"]
            fdeck = [vocab(it["text"]) for it in front if it["role"] == "deck"]
            cont = [it for it in cont if not (it["role"] == "deck" and any(
                fd and len(fd & vocab(it["text"])) / len(fd) >= 0.6 for fd in fdeck))]      # deck lines the story page repeats
            jh = best["headline"].strip()
            if jh:
                jv = vocab(jh)
                known = vocab(" ".join([st["headline"]] + [it["text"] for it in front]))
                if jv and len(jv & known) / len(jv) >= 0.5:
                    if st["graphic"] and not st["headline_from"]:
                        # the story's own headline is a picture; the continuation carries it as text
                        st["kicker"] = st["headline"]
                        st["headline"], st["headline_from"] = jh, "continuation"
                else:
                    cont.insert(0, {"role": "subhead", "text": jh})
                    self.join_log["kept_jump_headings"].append((st["id"], n, jh))
            # a subheading that only repeats the story's own headline / deck words (the story page prints them again) is dropped
            hv = vocab(" ".join([st["headline"]] + [it["text"] for it in front if it["role"] == "deck"]))
            cont = [it for it in cont if not (it["role"] == "subhead" and vocab(it["text"]) and
                                              len(vocab(it["text"]) & hv) / len(vocab(it["text"])) >= 0.7)]
            # a sentence cut by the page break: the last front paragraph does not end a sentence and the next item is body text
            if front and cont and front[-1]["role"] == "body" and cont[0]["role"] == "body" \
                    and not re.search(r"[.?!\u2026\u0964'\"\u2019\u201d)]\s*$", front[-1]["text"]):
                front[-1] = {"role": "body", "text": self._join_lines([front[-1]["text"], cont[0]["text"]])}
                cont = cont[1:]
                self.join_log["sentences_rejoined"] += 1
            st["items"] = front + cont
            st["paras"] = st["paras"] + ([jh] if jh else []) + best["paras"]
            st["words"] += best["words"]
        # stories whose continuation could not be matched: a display-only note, never part of the narration
        for st in stories:
            for c in st["contTo"]:
                if not c["linked"]:
                    st["items"] = [it for it in st["items"] if it["role"] != "marker"] + \
                        [{"role": "marker", "text": "continues on page %d, part not matched" % c["page"], "display_only": True}]
        for st in stories:
            if all(c["linked"] for c in st["contTo"]):
                st["items"] = [it for it in st["items"] if it["role"] != "marker"]
            st["headline"] = self._clean_reading(st["headline"])
            seen_heads = {st["headline"]}
            clean_items = []
            for it in st["items"]:
                text = self._clean_reading(it["text"])
                if not text or (it["role"] == "subhead" and text in seen_heads):
                    continue
                if it["role"] == "subhead":
                    seen_heads.add(text)
                clean_items.append(dict(it, text=text))
            st["items"] = clean_items
            st["narration"] = self._narration(st)
        shown = [s for s in stories if not s["hidden"]]
        sections = []
        for name in self.SECTION_ORDER:
            items = [s for s in shown if s["section"] == name]
            if items:
                sections.append({"name": name, "title": self.SECTION_TITLE.get(name, name), "stories": items})
        return {"sections": sections, "byId": {s["id"]: s for s in shown}}

    def crop(self, edition, date, pno, box):
        """JPEG of one block, cut from the page by its box (fractions of the page), cached under the state dir."""
        with self._lock:
            doc = self.doc(edition, date)
            if doc is None or not 1 <= pno <= len(doc):
                return None
            x0, y0, x1, y1 = box
            if not (0 <= x0 < x1 <= 1 and 0 <= y0 < y1 <= 1):
                return None
            os.makedirs(os.path.join(self.state_dir, "crops"), exist_ok=True)
            cache = os.path.join(self.state_dir, "crops", "%s_%s_p%d_%d_%d_%d_%d.jpg" % (
                edition, date, pno, *(int(round(v * 10000)) for v in box)))
            if not os.path.exists(cache):
                pg = doc[pno - 1]
                W, H = pg.rect.width, pg.rect.height
                pad = 3
                clip = pymupdf.Rect(max(x0 * W - pad, 0), max(y0 * H - pad, 0), min(x1 * W + pad, W), min(y1 * H + pad, H))
                pix = pg.get_pixmap(matrix=pymupdf.Matrix(CROP_ZOOM, CROP_ZOOM), clip=clip)
                with open(cache, "wb") as f:
                    f.write(pix.tobytes("jpeg", jpg_quality=80))
            with open(cache, "rb") as f:
                return f.read()

    def image(self, edition, date, pno):
        with self._lock:
            return self._image(edition, date, pno)

    def _image(self, edition, date, pno):
        doc = self.doc(edition, date)
        if doc is None or not 1 <= pno <= len(doc):
            return None
        cache = os.path.join(self.state_dir, "images", "%s_%s_p%d.jpg" % (edition, date, pno))
        if not os.path.exists(cache):
            pix = doc[pno - 1].get_pixmap(matrix=pymupdf.Matrix(IMG_ZOOM, IMG_ZOOM))
            with open(cache, "wb") as f:
                f.write(pix.tobytes("jpeg", jpg_quality=80))
        with open(cache, "rb") as f:
            return f.read()

    def results_path(self, edition, date):
        return os.path.join(self.state_dir, "results_%s_%s.json" % (edition, date))


def make_handler(store, key, web_dir):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=web_dir, **kw)

        def end_headers(self):
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
            super().end_headers()

        def log_message(self, fmt, *args):  # never log the key
            super().log_message(fmt, *[re.sub(r"k=[^& ]+", "k=…", str(a)) for a in args])

        def _authed(self, q):
            cookie = self.headers.get("Cookie", "")
            return secrets.compare_digest(
                next((c.split("=", 1)[1] for c in cookie.split("; ") if c.startswith("evk=")), ""), key
            )

        def _send(self, code, body, ctype="application/json", extra=None):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)

        def _json(self, code, obj):
            self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"))

        def _handle_api(self, method):
            u = urllib.parse.urlparse(self.path)
            q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
            if not self._authed(q):
                return self._json(401, {"error": "key required"})
            route = u.path[len("/review-api/"):]
            ed, date = q.get("edition", ""), q.get("date", "")
            try:
                pno = int(q.get("page", "0"))
            except ValueError:
                return self._json(400, {"error": "bad page"})
            if route == "editions":
                return self._json(200, store.editions())
            if store._pdf_path(ed, date)[0] is None:
                return self._json(404, {"error": "unknown edition"})
            if route == "page":
                p = store.page(ed, date, pno)
                return self._json(200, p) if p else self._json(404, {"error": "no page"})
            if route == "image":
                img = store.image(ed, date, pno)
                return self._send(200, img, "image/jpeg") if img else self._json(404, {"error": "no page"})
            if route == "paper":
                pp = store.paper(ed, date)
                if pp is None:
                    return self._json(404, {"error": "no such edition"})
                return self._json(200, {"sections": [
                    {"name": sec["name"], "title": sec["title"], "stories": [
                        {"id": st["id"], "page": st["page"], "headline": st["headline"], "graphic": bool(st["graphic"]),
                         "words": st["words"], "preview": next((it["text"] for it in st["items"] if it["role"] == "body"), "")[:150],
                         "continued": bool(st["contTo"]), "unmatched": any(not c["linked"] for c in st["contTo"])}
                        for st in sec["stories"]]} for sec in pp["sections"]]})
            if route == "story":
                pp = store.paper(ed, date)
                st = (pp or {}).get("byId", {}).get(q.get("id", ""))
                if st is None:
                    return self._json(404, {"error": "no such story"})
                return self._json(200, st)
            if route == "crop":
                try:
                    box = [float(v) for v in q.get("box", "").split(",")]
                    assert len(box) == 4
                except (ValueError, AssertionError):
                    return self._json(400, {"error": "bad box"})
                img = store.crop(ed, date, pno, box)
                return self._send(200, img, "image/jpeg") if img else self._json(404, {"error": "no such crop"})
            if route == "results":
                path = store.results_path(ed, date)
                if method == "GET":
                    data = {}
                    if os.path.exists(path):
                        with open(path, encoding="utf-8") as f:
                            data = json.load(f)
                    return self._json(200, data)
                n = int(self.headers.get("Content-Length", "0"))
                if n > 2_000_000:
                    return self._json(413, {"error": "too large"})
                try:
                    data = json.loads(self.rfile.read(n))
                    assert isinstance(data, dict)
                except (ValueError, AssertionError):
                    return self._json(400, {"error": "bad json"})
                fd, tmp = tempfile.mkstemp(dir=store.state_dir)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump(data, f, ensure_ascii=False, indent=1)
                os.replace(tmp, path)  # atomic: a crash never leaves half a file
                return self._json(200, {"ok": True})
            return self._json(404, {"error": "unknown route"})

        def do_GET(self):
            u = urllib.parse.urlparse(self.path)
            if u.path.startswith("/review-api/"):
                return self._handle_api("GET")
            q = urllib.parse.parse_qs(u.query)
            if "k" in q and secrets.compare_digest(q["k"][0], key):
                # First visit with the key: set a cookie, drop the key from the URL.
                return self._send(
                    302, b"", "text/plain",
                    {"Location": u.path or "/", "Set-Cookie": "evk=%s; HttpOnly; SameSite=Strict; Path=/" % key},
                )
            # Single-page app: any path that is not a real file gets index.html.
            if not os.path.exists(self.translate_path(u.path)):
                self.path = "/index.html"
            return super().do_GET()

        def do_PUT(self):
            if self.path.startswith("/review-api/"):
                return self._handle_api("PUT")
            return self._json(405, {"error": "method not allowed"})

    return Handler


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8090)
    ap.add_argument("--drive", default=os.path.expanduser(
        "~/Library/CloudStorage/GoogleDrive-pothulapatisiddhartha@gmail.com/My Drive/sohum-gativani"))
    ap.add_argument("--font-dir", default=os.path.expanduser("~/Workspace/sohum-veda-work/eenadu-font"))
    ap.add_argument("--glyph-dir", default=os.path.expanduser("~/Workspace/sohum-veda-work/eenadu-glyph"))
    ap.add_argument("--state-dir", default=os.path.expanduser("~/eenadu-review"))
    ap.add_argument("--web", default=os.path.join(here, "..", "packages", "app", "build", "web"))
    ap.add_argument("--local-only", action="store_true", help="bind 127.0.0.1 instead of the LAN")
    a = ap.parse_args()

    store = Store(a.drive, a.font_dir, a.glyph_dir, a.state_dir)
    key = secrets.token_urlsafe(16)
    bind = "127.0.0.1" if a.local_only else "0.0.0.0"
    srv = http.server.ThreadingHTTPServer((bind, a.port), make_handler(store, key, os.path.abspath(a.web)))
    host = "localhost" if a.local_only else lan_ip()
    print("Eenadu review server. Open this on your phone (same Wi-Fi):")
    print("  http://%s:%d/review?k=%s" % (host, a.port, key))
    print("Results are saved in", a.state_dir, "- Ctrl-C to stop.", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
