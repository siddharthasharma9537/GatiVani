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
  GET  page?edition=&date=&page=      -> {width, height, blocks:[{id, box, lines:[{converted, ocr}]}]}
  GET  image?edition=&date=&page=     -> JPEG of the page
  GET  results?edition=&date=         -> {blockId: {verdict, note}}
  PUT  results?edition=&date=         -> same shape, replaces the file
"""
import argparse
import glob
import http.server
import json
import os
import re
import secrets
import socket
import tempfile
import urllib.parse

import pymupdf

BODY_FONT = "Eenadu-Light"  # the only font the converter table covers
IMG_ZOOM = 1.4


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
    def __init__(self, drive, font_dir, state_dir):
        self.drive, self.font_dir, self.state_dir = drive, font_dir, state_dir
        os.makedirs(os.path.join(state_dir, "images"), exist_ok=True)
        with open(os.path.join(font_dir, "table_v2.json"), encoding="utf-8") as f:
            self.table = json.load(f)
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

    def _decode(self, codes):
        return "".join(self.table.get(c, ["?"])[0] if c != " " else " " for c in codes)

    def _ocr_by_bbox(self, edition, date, pno):
        # Tesseract line readings exist only for the page set the converter was
        # trained on (Telangana, 12-11-2026); everything else shows no OCR.
        if (edition, date) != ("TELANGANA", "12-11-2026"):
            return {}
        p = os.path.join(self.font_dir, "lines_p%d.json" % pno)
        if not os.path.exists(p):
            return {}
        with open(p, encoding="utf-8") as f:
            rows = json.load(f)
        return {tuple(round(v, 2) for v in r["bbox"]): re.sub("[​‌‍]", "", r["ocr"]) for r in rows}

    def page(self, edition, date, pno):
        doc = self.doc(edition, date)
        if doc is None or not 1 <= pno <= len(doc):
            return None
        pg = doc[pno - 1]
        W, H = pg.rect.width, pg.rect.height
        ocr = self._ocr_by_bbox(edition, date, pno)
        blocks = []
        for bi, b in enumerate(pg.get_text("rawdict")["blocks"]):
            lines, x0, y0, x1, y1 = [], 1e9, 1e9, 0, 0
            for l in b.get("lines", []):
                sp = l["spans"]
                if not sp or any(s["font"].split("+")[-1] != BODY_FONT for s in sp):
                    continue
                codes = "".join(ch["c"] for s in sp for ch in s["chars"])
                if len(codes.strip()) < 12:
                    continue
                bb = l["bbox"]
                x0, y0, x1, y1 = min(x0, bb[0]), min(y0, bb[1]), max(x1, bb[2]), max(y1, bb[3])
                lines.append({
                    "converted": self._decode(codes),
                    "ocr": ocr.get(tuple(round(v, 2) for v in bb)),
                })
            if lines:
                blocks.append({"id": "%d:%d" % (pno, bi), "box": [x0 / W, y0 / H, x1 / W, y1 / H], "lines": lines})
        return {"width": W, "height": H, "blocks": blocks}

    def image(self, edition, date, pno):
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
    ap.add_argument("--state-dir", default=os.path.expanduser("~/eenadu-review"))
    ap.add_argument("--web", default=os.path.join(here, "..", "packages", "app", "build", "web"))
    ap.add_argument("--local-only", action="store_true", help="bind 127.0.0.1 instead of the LAN")
    a = ap.parse_args()

    store = Store(a.drive, a.font_dir, a.state_dir)
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
