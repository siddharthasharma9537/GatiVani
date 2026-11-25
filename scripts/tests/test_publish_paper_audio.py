"""Fake clients only: no network, no Cloudflare, no Supabase. Synthetic ids and text."""
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import publish_paper_audio as P

NOW = datetime.datetime(2026, 11, 25, 5, 40, 12, tzinfo=datetime.timezone.utc)
DATE, ED, BUCKET = '25-11-2026', 'TELANGANA', 'gativani-paper-audio'


def make_dir(stories=None, files=None):
    d = tempfile.mkdtemp()
    stories = stories or [
        {'id': 'sample_lead', 'rank': 1, 'page': 1, 'edition': ED, 'headline': 'నమూనా వార్త', 'chars': 100,
         'file': '001_sample_lead.m4a', 'audio_seconds': 60.0, 'status': 'ok'},
        {'id': 'sample_two', 'rank': 2, 'page': 2, 'edition': ED, 'headline': 'రెండవ వార్త', 'chars': 50,
         'file': '002_sample_two.m4a', 'audio_seconds': 30.0, 'status': 'ok'},
        {'id': 'sample_failed', 'rank': 3, 'page': 2, 'edition': ED, 'headline': 'x', 'chars': 5,
         'file': '003_sample_failed.m4a', 'audio_seconds': 1.0, 'status': 'failed'},
    ]
    with open(os.path.join(d, 'manifest.json'), 'w', encoding='utf-8') as f:
        json.dump({'model': 'bulbul:v4-flash', 'speaker': 'tarun_te_narration', 'stories': stories},
                  f, ensure_ascii=False)
    for s in stories:
        if s['status'] == 'ok':
            Path(d, s['file']).write_bytes((files or {}).get(s['file'], b'audio-' + s['id'].encode()))
    return d


class FakeR2:
    def __init__(self):
        self.objects, self.calls = {}, []

    def stored_sha256(self, key):
        self.calls.append(('head', key))
        return self.objects.get(key, (None, None))[1]

    def put(self, key, data, sha):
        self.calls.append(('put', key))
        self.objects[key] = (data, sha)

    def list_keys(self, pre):
        return sorted(k for k in self.objects if k.startswith(pre))

    def delete(self, key):
        self.calls.append(('delete', key))
        self.objects.pop(key, None)


class FakeRows:
    def __init__(self):
        self.calls = []

    def upsert(self, rows):
        self.calls.append(('upsert', rows))

    def prune(self, e, d, ids):
        self.calls.append(('prune', e, d, list(ids)))

    def delete_day(self, e, d):
        self.calls.append(('delete_day', e, d))


class BuildRows(unittest.TestCase):
    def test_rows_follow_the_contract_and_skip_failed(self):
        rows, skipped = P.build_rows(make_dir(), DATE, ED, BUCKET, NOW)
        self.assertEqual(skipped, ['sample_failed'])
        r = rows[0]
        self.assertEqual(r['object_key'], 'paper/TELANGANA/25-11-2026/001_sample_lead.m4a')
        self.assertEqual(r['content_type'], 'audio/mp4')
        self.assertEqual(r['sha256'], hashlib.sha256(b'audio-sample_lead').hexdigest())
        self.assertEqual((r['voice'], r['model'], r['characters']), ('tarun_te_narration', 'bulbul:v4-flash', 100))
        self.assertEqual([x['rank'] for x in rows], [1, 2])
        self.assertFalse(r['object_key'].startswith('http'))

    def test_duplicate_rank_or_bad_id_is_rejected(self):
        base = {'edition': ED, 'page': 1, 'headline': 'h', 'chars': 1, 'audio_seconds': 1.0, 'status': 'ok'}
        dup = [dict(base, id='a', rank=1, file='a.m4a'), dict(base, id='b', rank=1, file='b.m4a')]
        with self.assertRaises(ValueError):
            P.build_rows(make_dir(dup), DATE, ED, BUCKET, NOW)
        bad = [dict(base, id='Bad Id', rank=1, file='a.m4a')]
        with self.assertRaises(ValueError):
            P.build_rows(make_dir(bad), DATE, ED, BUCKET, NOW)

    def test_public_row_hides_local_path_and_uses_iso_date(self):
        row = P.public_row(P.build_rows(make_dir(), DATE, ED, BUCKET, NOW)[0][0])
        self.assertNotIn('_path', row)
        self.assertEqual(row['source_date'], '2026-11-25')


class Publish(unittest.TestCase):
    def run_publish(self, d, r2, rows, dry=False):
        out = []
        P.publish_audio_day(d, DATE, ED, BUCKET, dry_run=dry, r2=r2, rows_api=rows, output=out.append, now=NOW)
        return out

    def test_dry_run_touches_nothing(self):
        r2, rows = FakeR2(), FakeRows()
        out = self.run_publish(make_dir(), r2, rows, dry=True)
        self.assertEqual((r2.calls, rows.calls), ([], []))
        self.assertIn('(dry run)', out[0])
        self.assertNotIn('నమూనా', '\n'.join(out))

    def test_publish_uploads_then_writes_rows_and_is_idempotent(self):
        d, r2, rows = make_dir(), FakeR2(), FakeRows()
        self.run_publish(d, r2, rows)
        self.assertEqual(len(r2.objects), 2)
        self.assertEqual([c[0] for c in rows.calls], ['upsert', 'prune'])
        self.assertEqual(rows.calls[0][1][0]['source_date'], '2026-11-25')
        r2.calls.clear()
        out = self.run_publish(d, r2, FakeRows())
        self.assertNotIn(('put', 'paper/TELANGANA/25-11-2026/001_sample_lead.m4a'), r2.calls)
        self.assertIn('0 uploaded, 2 unchanged', out[-1])

    def test_changed_file_is_replaced_and_stale_object_removed(self):
        d, r2 = make_dir(), FakeR2()
        self.run_publish(d, r2, FakeRows())
        r2.objects['paper/TELANGANA/25-11-2026/009_old.m4a'] = (b'x', 'y')
        Path(d, '001_sample_lead.m4a').write_bytes(b'new audio')
        out = self.run_publish(d, r2, FakeRows())
        self.assertEqual(r2.objects['paper/TELANGANA/25-11-2026/001_sample_lead.m4a'][0], b'new audio')
        self.assertNotIn('paper/TELANGANA/25-11-2026/009_old.m4a', r2.objects)
        self.assertIn('1 uploaded, 1 unchanged, 1 stale', out[-1])

    def test_failed_upload_writes_no_rows(self):
        class Boom(FakeR2):
            def put(self, *a):
                raise RuntimeError('Storage request failed (HTTP 500)')
        rows = FakeRows()
        with self.assertRaises(RuntimeError):
            self.run_publish(make_dir(), Boom(), rows)
        self.assertEqual(rows.calls, [])

    def test_empty_publication_refused(self):
        stories = [{'id': 'a', 'rank': 1, 'page': 1, 'edition': ED, 'headline': 'h', 'chars': 1,
                    'file': 'a.m4a', 'audio_seconds': 1.0, 'status': 'failed'}]
        with self.assertRaises(ValueError):
            self.run_publish(make_dir(stories), FakeR2(), FakeRows())


class DeleteDay(unittest.TestCase):
    def test_files_first_then_rows(self):
        r2, rows = FakeR2(), FakeRows()
        for k in ('paper/TELANGANA/25-11-2026/001_a.m4a', 'paper/TELANGANA/25-11-2026/002_b.m4a',
                  'paper/TELANGANA/26-11-2026/001_c.m4a'):
            r2.objects[k] = (b'x', 'y')
        P.delete_audio_day(DATE, ED, r2=r2, rows_api=rows, output=lambda s: None)
        self.assertEqual(list(r2.objects), ['paper/TELANGANA/26-11-2026/001_c.m4a'])
        self.assertEqual(rows.calls, [('delete_day', ED, DATE)])

    def test_rows_kept_if_files_remain(self):
        class Sticky(FakeR2):
            def delete(self, key):
                pass
        r2, rows = Sticky(), FakeRows()
        r2.objects['paper/TELANGANA/25-11-2026/001_a.m4a'] = (b'x', 'y')
        with self.assertRaises(RuntimeError):
            P.delete_audio_day(DATE, ED, r2=r2, rows_api=rows, output=lambda s: None)
        self.assertEqual(rows.calls, [])

    def test_dry_run(self):
        r2, rows = FakeR2(), FakeRows()
        P.delete_audio_day(DATE, ED, dry_run=True, r2=r2, rows_api=rows, output=lambda s: None)
        self.assertEqual((r2.calls, rows.calls), ([], []))


class Signing(unittest.TestCase):
    def test_aws_documented_get_object_example(self):
        # The "GET Object with Range header" example from the AWS Signature V4 documentation.
        h = P.sigv4_headers('GET', 'examplebucket.s3.amazonaws.com', '/test.txt', {}, {'range': 'bytes=0-9'},
                            hashlib.sha256(b'').hexdigest(), 'AKIAIOSFODNN7EXAMPLE',
                            'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', '20130524T000000Z',
                            region='us-east-1')
        self.assertTrue(h['authorization'].endswith(
            'Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41'))
        self.assertIn('SignedHeaders=host;range;x-amz-content-sha256;x-amz-date', h['authorization'])


class Clients(unittest.TestCase):
    class Resp:
        def __init__(self, status=200, body=b'', headers=None):
            self.status, self.body, self.headers = status, body, headers or {}
        def read(self): return self.body
        def __enter__(self): return self
        def __exit__(self, *a): return False

    def test_r2_put_head_list_and_error_text_is_generic(self):
        seen = []
        def opener(req, timeout):
            seen.append((req.method, req.full_url, dict(req.headers)))
            if req.method == 'GET':
                return self.Resp(body=b'<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Contents><Key>paper/a</Key></Contents><IsTruncated>false</IsTruncated></ListBucketResult>')
            return self.Resp(headers={'x-amz-meta-sha256': 'abc'})
        c = P.R2Client('acct', 'AK', 'SECRET', 'b', opener, clock=lambda: NOW)
        c.put('paper/x.m4a', b'data', 'abc')
        self.assertEqual(c.stored_sha256('paper/x.m4a'), 'abc')
        self.assertEqual(c.list_keys('paper/'), ['paper/a'])
        self.assertEqual(seen[0][1], 'https://acct.r2.cloudflarestorage.com/b/paper/x.m4a')
        self.assertNotIn('SECRET', json.dumps(seen))
        self.assertEqual(seen[0][2]['X-amz-meta-sha256'], 'abc')

    def test_http_error_hides_body(self):
        import urllib.error
        def opener(req, timeout):
            raise urllib.error.HTTPError(req.full_url, 403, 'SECRET-LEAK', {}, io.BytesIO(b'SECRET-LEAK'))
        with self.assertRaises(RuntimeError) as cm:
            P.R2Client('a', 'k', 's', 'b', opener, clock=lambda: NOW).put('k', b'x', 'y')
        self.assertNotIn('SECRET', str(cm.exception))
        self.assertIn('403', str(cm.exception))

    def test_rest_rows_requires_https_origin_and_sends_owner_token(self):
        with self.assertRaises(ValueError):
            P.RestRows('http://x.example', 't', 'k')
        seen = []
        def opener(req, timeout):
            seen.append(req)
            return self.Resp()
        rows = P.RestRows('https://x.supabase.co', 'tok', 'key', opener)
        rows.upsert([{'story_id': 'a'}])
        rows.prune(ED, DATE, ['a', 'b'])
        rows.delete_day(ED, DATE)
        self.assertIn('on_conflict=edition%2Csource_date%2Cstory_id', seen[0].full_url)
        self.assertEqual(seen[0].headers['Authorization'], 'Bearer tok')
        self.assertIn('story_id=not.in.', seen[1].full_url)
        self.assertIn('source_date=eq.2026-11-25', seen[2].full_url)


class Main(unittest.TestCase):
    def test_dry_run_needs_no_environment_and_prints_no_headlines(self):
        d = make_dir()
        buf = io.StringIO()
        with patch.dict(os.environ, {}, clear=True), patch('sys.stdout', buf):
            code = P.main(['--date', DATE, '--edition', ED, '--audio-dir', d, '--dry-run'])
        self.assertEqual(code, 0)
        self.assertNotIn('నమూనా', buf.getvalue())

    def test_real_run_without_environment_fails_quietly(self):
        err = io.StringIO()
        with patch.dict(os.environ, {}, clear=True), patch('sys.stderr', err):
            self.assertEqual(P.main(['--date', DATE, '--edition', ED, '--audio-dir', make_dir()]), 1)
        self.assertNotIn('R2_', err.getvalue())

    def test_bad_date_rejected(self):
        with patch('sys.stderr', io.StringIO()):
            self.assertEqual(P.main(['--date', '2026-11-25', '--edition', ED, '--dry-run', '--audio-dir', 'x']), 1)


if __name__ == '__main__':
    unittest.main()
