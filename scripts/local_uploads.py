"""Private PDF upload jobs for the local review server; no network clients."""
import datetime
import glob
import hashlib
import json
import os
import re
import secrets
import shutil
import threading

import pymupdf

MAX_UPLOAD_BYTES = 100 * 1024 * 1024


class LocalUploads:
    def __init__(self, base):
        self.base = base
        self.root = os.path.join(base.state_dir, "uploads")
        os.makedirs(self.root, mode=0o700, exist_ok=True)
        self.jobs, self.stores, self.events = {}, {}, {}
        self.lock = threading.RLock()
        for path in glob.glob(os.path.join(self.root, "*", "job.json")):
            try:
                with open(path, encoding="utf-8") as f:
                    job = json.load(f)
                if job["status"] not in ("ready", "failed", "cancelled"):
                    job.update(status="failed", error="Server restarted. Upload the PDF again.")
                self.jobs[job["id"]] = job
            except (OSError, ValueError, KeyError):
                continue

    def _update(self, job_id, **patch):
        with self.lock:
            self.jobs[job_id].update(patch)
            path = os.path.join(self.root, job_id, "job.json")
            with open(path + ".tmp", "w", encoding="utf-8") as f:
                json.dump(self.jobs[job_id], f, ensure_ascii=False)
            os.replace(path + ".tmp", path)

    def status(self, job_id):
        with self.lock:
            return dict(self.jobs[job_id]) if job_id in self.jobs else None

    def cancel(self, job_id):
        with self.lock:
            job = self.jobs.get(job_id)
            if job is None:
                return None
            if job["status"] not in ("ready", "failed", "cancelled"):
                self.events[job_id].set()
                self._update(job_id, status="cancelled", stage="Cancelled")
            return self.status(job_id)

    def editions(self):
        with self.lock:
            return [dict(edition=j["edition"], date=j["date"], pages=j["totalPages"], title=j["filename"])
                    for j in self.jobs.values() if j["status"] == "ready"]

    def _store(self, job):
        folder = os.path.join(self.root, job["id"])
        child = type(self.base)(folder, self.base.font_dir, self.base.glyph_dir, folder,
                                cancel_event=self.events.get(job["id"]))
        child.display_title = job["filename"]
        result = os.path.join(folder, "paper.json")
        if os.path.exists(result):
            with open(result, encoding="utf-8") as f:
                child._paper_cache[(job["edition"], job["date"])] = json.load(f)
        return child

    def store_for(self, edition, date):
        with self.lock:
            job = next((j for j in self.jobs.values() if j["edition"] == edition and j["date"] == date and j["status"] == "ready"), None)
            if job is None:
                return None
            if job["id"] not in self.stores:
                self.stores[job["id"]] = self._store(job)
            return self.stores[job["id"]]

    def start(self, source, size, filename):
        if not 0 < size <= MAX_UPLOAD_BYTES:
            raise ValueError("Choose a PDF smaller than 100 MB.")
        filename = os.path.basename(filename.replace("\\", "/"))
        if not filename.lower().endswith(".pdf"):
            raise ValueError("Local extraction accepts PDF files only.")
        with self.lock:
            if any(j["status"] not in ("ready", "failed", "cancelled") for j in self.jobs.values()):
                raise ValueError("An extraction is already running. Wait or cancel it first.")
            job_id = secrets.token_hex(8)
            edition = "LOCAL-" + job_id
            match = re.search(r"(\d{2}-\d{2}-\d{4})", filename)
            date = match.group(1) if match else datetime.date.today().strftime("%d-%m-%Y")
            datetime.datetime.strptime(date, "%d-%m-%Y")
            folder = os.path.join(self.root, job_id)
            os.makedirs(folder, mode=0o700)
            pdf_name = "Eenadu_%s_%s.pdf" % (edition, date)
            path = os.path.join(folder, pdf_name)
            try:
                remaining = size
                with open(path, "wb") as f:
                    while remaining:
                        chunk = source.read(min(1024 * 1024, remaining))
                        if not chunk:
                            raise ValueError("Upload ended before the PDF was received.")
                        f.write(chunk)
                        remaining -= len(chunk)
                os.chmod(path, 0o600)
                with pymupdf.open(path) as doc:
                    if not doc.is_pdf or doc.needs_pass or not 0 < len(doc) <= 100:
                        raise ValueError("Use an unlocked PDF with 1–100 pages.")
                    pages = len(doc)
                # Reuse local page labels/jumps only for the exact same daily PDF.
                original = os.path.join(self.base.drive, filename)
                sidecar = os.path.splitext(original)[0] + ".links.json"
                if os.path.isfile(original) and os.path.isfile(sidecar):
                    with open(path, "rb") as a, open(original, "rb") as b:
                        same = hashlib.file_digest(a, "sha256").digest() == hashlib.file_digest(b, "sha256").digest()
                    if same:
                        shutil.copyfile(sidecar, os.path.splitext(path)[0] + ".links.json")
                with open(os.path.join(folder, "manifest-%s.json" % date), "w", encoding="utf-8") as f:
                    json.dump(dict(date=date, editions={edition: dict(status="ok", pdf=pdf_name, pages=pages)}), f)
            except Exception:
                shutil.rmtree(folder)
                raise
            self.jobs[job_id] = dict(id=job_id, edition=edition, date=date, filename=filename,
                                     status="extracting", stage="Reading pages", donePages=0, totalPages=pages,
                                     articles=0, error=None)
            self.events[job_id] = threading.Event()
            self._update(job_id)
            threading.Thread(target=self._run, args=(job_id,), daemon=True).start()
            return self.status(job_id)

    def _run(self, job_id):
        child = None
        try:
            job = self.status(job_id)
            child = self._store(job)
            for page in range(1, job["totalPages"] + 1):
                child.page(job["edition"], job["date"], page)
                self._update(job_id, donePages=page)
            self._update(job_id, stage="Grouping stories and continuations")
            paper = child.paper(job["edition"], job["date"])
            if self.events[job_id].is_set():
                raise InterruptedError()
            if not paper["byId"]:
                raise ValueError("No supported text layer found. Scanned or graphic-only pages need local OCR.")
            folder = os.path.join(self.root, job_id)
            with open(os.path.join(folder, "paper.json"), "w", encoding="utf-8") as f:
                json.dump(paper, f, ensure_ascii=False)
            with self.lock:
                if self.events[job_id].is_set():
                    raise InterruptedError()
                self.stores[job_id] = child
                self._update(job_id, status="ready", stage="Ready", articles=len(paper["byId"]))
        except InterruptedError:
            self._update(job_id, status="cancelled", stage="Cancelled")
        except Exception as e:
            self._update(job_id, status="failed", stage="Extraction failed", error=str(e)[:300])
        finally:
            if child is not None and self.status(job_id)["status"] != "ready":
                for doc in child._docs.values():
                    doc.close()
