"""Local upload lifecycle, limits and authentication; no publisher content."""
import io
import json
import os
import tempfile
import time
import unittest
from unittest.mock import patch

import pymupdf
from local_uploads import LocalUploads, MAX_UPLOAD_BYTES
from eenadu_review_server import make_handler


class FixtureStore:
    def __init__(self, drive, font_dir, glyph_dir, state_dir, cancel_event=None):
        self.drive, self.font_dir, self.glyph_dir, self.state_dir = drive, font_dir, glyph_dir, state_dir
        self._paper_cache, self._docs = {}, {}
        self.cancel_event = cancel_event

    def page(self, edition, date, page):
        if self.cancel_event is not None and self.cancel_event.is_set():
            raise InterruptedError()
        return {'blocks': []}

    def paper(self, edition, date):
        story = dict(id='p1-g0', headline='A garden visit', items=[], narration='A garden visit')
        return self._paper_cache.get((edition, date), {'sections': [], 'byId': {'p1-g0': story}})


def pdf():
    with pymupdf.open() as doc:
        doc.new_page().insert_text((30, 30), 'Neutral synthetic fixture')
        return doc.tobytes()


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = FixtureStore(self.tmp.name, self.tmp.name, self.tmp.name, self.tmp.name)
        self.jobs = LocalUploads(self.base)
        self.data = pdf()

    def wait(self, job_id):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            job = self.jobs.status(job_id)
            if job['status'] != 'extracting':
                return job
            time.sleep(.01)
        self.fail('local extraction did not finish')

    def test_ready_upload_survives_restart_and_keeps_files_private(self):
        job = self.jobs.start(io.BytesIO(self.data), len(self.data), '../../garden_16-11-2026.pdf')
        job = self.wait(job['id'])
        self.assertEqual(job['status'], 'ready')
        self.assertEqual((job['totalPages'], job['donePages'], job['articles']), (1, 1, 1))
        self.assertEqual(job['filename'], 'garden_16-11-2026.pdf')
        self.assertEqual(os.stat(os.path.join(self.jobs.root, job['id'])).st_mode & 0o777, 0o700)
        restarted = LocalUploads(self.base)
        self.assertEqual(restarted.editions()[0]['edition'], job['edition'])
        child = restarted.store_for(job['edition'], job['date'])
        self.assertEqual(len(child.paper(job['edition'], job['date'])['byId']), 1)
        self.assertIsNone(restarted.store_for('unknown', job['date']))

    def test_rejects_large_non_pdf_and_truncated_uploads(self):
        for source, size, name in [(io.BytesIO(), MAX_UPLOAD_BYTES + 1, 'x.pdf'),
                                   (io.BytesIO(self.data), len(self.data), 'x.jpg'),
                                   (io.BytesIO(self.data[:20]), len(self.data), 'x.pdf'),
                                   (io.BytesIO(b'not a pdf'), 9, 'x.pdf')]:
            with self.assertRaises(Exception):
                self.jobs.start(source, size, name)
        self.assertEqual(os.listdir(self.jobs.root), [])

    def test_cancel_is_persisted_and_a_second_active_job_is_rejected(self):
        with patch.object(LocalUploads, '_run', return_value=None):
            job = self.jobs.start(io.BytesIO(self.data), len(self.data), 'x.pdf')
            with self.assertRaisesRegex(ValueError, 'already running'):
                self.jobs.start(io.BytesIO(self.data), len(self.data), 'y.pdf')
            cancelled = self.jobs.cancel(job['id'])
            self.assertEqual(cancelled['status'], 'cancelled')
            self.assertTrue(self.jobs.events[job['id']].is_set())
        self.assertEqual(LocalUploads(self.base).status(job['id'])['status'], 'cancelled')
        self.assertEqual(self.jobs.editions(), [])

    def test_empty_extraction_fails_with_actionable_ocr_message(self):
        with patch.object(FixtureStore, 'paper', return_value={'byId': {}}):
            job = self.jobs.start(io.BytesIO(self.data), len(self.data), 'x.pdf')
            final = self.wait(job['id'])
        self.assertEqual(final['status'], 'failed')
        self.assertIn('local OCR', final['error'])
        self.assertEqual(self.jobs.editions(), [])

    def test_restart_marks_interrupted_job_failed(self):
        with patch.object(LocalUploads, '_run', return_value=None):
            job = self.jobs.start(io.BytesIO(self.data), len(self.data), 'x.pdf')
        recovered = LocalUploads(self.base).status(job['id'])
        self.assertEqual(recovered['status'], 'failed')
        self.assertIn('restarted', recovered['error'])

    def test_upload_and_cancel_require_auth_and_same_origin(self):
        Handler = make_handler(self.base, 'test-key', self.tmp.name)
        handler = Handler.__new__(Handler)
        handler.rfile = io.BytesIO(self.data)
        handler._json = lambda code, data: (code, data)
        handler.path = '/review-api/upload'
        handler.headers = {'Host': '127.0.0.1:8097', 'Content-Length': str(len(self.data))}
        self.assertEqual(handler._handle_api('POST')[0], 401)
        handler.headers['Cookie'] = 'evk=test-key'
        handler.headers['Origin'] = 'http://unrelated.example'
        self.assertEqual(handler._handle_api('POST')[0], 403)
        handler.path = '/review-api/cancel-upload?id=unknown'
        self.assertEqual(handler._handle_api('POST')[0], 403)
        handler.headers['Origin'] = 'http://127.0.0.1:8097'
        self.assertEqual(handler._handle_api('POST')[0], 404)
        handler.path = '/review-api/upload'
        handler.headers['Content-Length'] = str(MAX_UPLOAD_BYTES + 1)
        self.assertEqual(handler._handle_api('POST')[0], 413)


if __name__ == '__main__':
    unittest.main()
