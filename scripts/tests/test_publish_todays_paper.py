"""Synthetic text only; Telugu sentences are AI proposals, not publisher text."""
import copy
import io
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import urllib.error
import urllib.parse

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publish_todays_paper import RestPublisher, main, publish_day, rows_from_paper, SECTIONS


def paper():
    return {'sections': [{'name': 'Front page', 'stories': [{
        'id': 'p1-g0', 'page': 1, 'headline': 'తోటలో చెట్లు', 'kicker': 'ప్రకృతి',
        'graphic': [0.1, 0.1, 0.2, 0.2], 'words': 4,
        'contTo': [{'page': 2, 'linked': True}, {'page': 3, 'linked': False}],
        'items': [{'role': 'byline', 'text': 'రచయిత'},
                  {'role': 'subhead', 'text': 'పూల రంగులు'},
                  {'role': 'body', 'text': 'తోటలో పూలు వికసించాయి.'},
                  {'role': 'caption', 'text': 'పూల చిత్రం'},
                  {'role': 'sidebar', 'text': 'మొక్కలకు నీరు అవసరం.'},
                  {'role': 'marker', 'text': 'continues on page 3, part not matched'}],
        'narration': 'తోటలో చెట్లు\n\nపూల రంగులు\n\nతోటలో పూలు వికసించాయి.',
    }]}]}


class Store:
    def editions(self):
        return [{'edition': 'TELANGANA', 'date': '13-11-2026'}]

    def paper(self, edition, date):
        assert date == '13-11-2026'
        return paper()


class FakeHttp:
    """Models the RPC's replace/upsert contract; records HTTP, never uses sockets."""
    def __init__(self):
        self.calls, self.days = [], {}

    def __call__(self, request, timeout):
        self.calls.append(request)
        if request.method == 'POST':
            payload = json.loads(request.data)
            key = (payload['p_edition'], payload['p_date'])
            self.days[key] = {r['source_id']: r for r in payload['p_stories']}
        else:
            query = urllib.parse.parse_qs(urllib.parse.urlsplit(request.full_url).query)
            self.days.pop((query['edition'][0][3:], query['source_date'][0][3:]), None)
        return io.BytesIO(b'')


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.http = FakeHttp()
        self.publisher = RestPublisher('https://example.invalid', 'synthetic-token', 'synthetic-key', self.http)

    def test_roles_graphic_pages_narration_and_no_local_urls(self):
        row = rows_from_paper(paper())[0]
        self.assertEqual([i['role'] for i in row['items']], ['headline', 'kicker', 'byline', 'subheading', 'body', 'caption', 'side'])
        self.assertTrue(row['headline_is_graphic'])
        self.assertIsNone(row['headline_image_url'])
        self.assertEqual(row['page_numbers'], [1, 2])
        self.assertEqual(len(row['continuation_info']), 2)
        self.assertEqual(row['narration_text'], paper()['sections'][0]['stories'][0]['narration'])
        self.assertEqual(row['narration_text'].count('తోటలో చెట్లు'), 1)
        self.assertNotIn('marker', row['display_text'])
        self.assertNotIn('continues', row['narration_text'])
        self.assertNotIn('పూల చిత్రం', row['narration_text'])

    def test_dry_run_prints_all_section_counts_and_never_calls_http(self):
        output = []
        publish_day(Store(), '2026-11-13', ['TELANGANA'], dry_run=True, output=output.append)
        self.assertIn('TELANGANA 2026-11-13: 1 stories (dry run)', output)
        self.assertEqual(len(output), 13)
        self.assertIn('  Front page: 1', output)
        self.assertEqual(self.http.calls, [])

    def test_publish_twice_same_identity_and_replacement_removes_stale(self):
        for _ in range(2):
            publish_day(Store(), '2026-11-13', ['TELANGANA'], publisher=self.publisher, output=lambda _: None)
        key = ('TELANGANA', '2026-11-13')
        self.assertEqual(len(self.http.days[key]), 1)
        replacement = copy.deepcopy(paper())
        replacement['sections'][0]['stories'][0]['id'] = 'p1-g1'
        self.publisher.publish(*key, rows_from_paper(replacement))
        self.assertEqual(list(self.http.days[key]), ['p1-g1'])
        request = self.http.calls[0]
        self.assertEqual(request.full_url, 'https://example.invalid/rest/v1/rpc/publish_paper_day')
        self.assertEqual(request.get_header('Authorization'), 'Bearer synthetic-token')
        self.assertEqual(request.get_header('Apikey'), 'synthetic-key')

    def test_delete_is_scoped_and_idempotent_and_does_not_load_store(self):
        publish_day(Store(), '2026-11-13', ['TELANGANA'], publisher=self.publisher, output=lambda _: None)
        self.http.days[('TELANGANA', '2026-11-12')] = {'other': {}}
        for _ in range(2):
            publish_day(None, '2026-11-13', ['TELANGANA'], delete_day=True, publisher=self.publisher, output=lambda _: None)
        self.assertNotIn(('TELANGANA', '2026-11-13'), self.http.days)
        self.assertIn(('TELANGANA', '2026-11-12'), self.http.days)

    def test_dry_delete_without_env_or_store(self):
        with patch.dict(os.environ, {}, clear=True), patch('builtins.print'):
            self.assertEqual(main(['--date', '2026-11-13', '--editions', 'TELANGANA', '--delete-day', '--dry-run']), 0)
        self.assertEqual(self.http.calls, [])

    def test_missing_edition_validated_before_any_publish(self):
        with self.assertRaises(ValueError):
            publish_day(Store(), '2026-11-13', ['TELANGANA', 'ANDHRA-PRADESH'], publisher=self.publisher)
        self.assertEqual(self.http.calls, [])

    def test_empty_publication_requires_explicit_delete(self):
        store = Store()
        store.paper = lambda *_: {'sections': []}
        with self.assertRaises(ValueError):
            publish_day(store, '2026-11-13', ['TELANGANA'], publisher=self.publisher)
        self.assertEqual(self.http.calls, [])

    def test_duplicate_identity_or_unknown_role_is_rejected(self):
        data = paper()
        data['sections'][0]['stories'] *= 2
        with self.assertRaises(ValueError):
            rows_from_paper(data)
        data = paper()
        data['sections'][0]['stories'][0]['items'][0]['role'] = 'unexpected'
        with self.assertRaises(ValueError):
            rows_from_paper(data)

    def test_all_section_mappings(self):
        data = paper()
        original = data['sections'][0]
        data['sections'] = []
        for index, section in enumerate(SECTIONS):
            sec = copy.deepcopy(original)
            sec['name'] = section
            sec['stories'][0]['id'] = str(index)
            data['sections'].append(sec)
        rows = rows_from_paper(data)
        self.assertEqual([r['section'] for r in rows], list(SECTIONS.values()))
        self.assertEqual([r['sort_order'] for r in rows], list(range(12)))

    def test_errors_never_include_server_body_or_credentials(self):
        def fail(request, timeout):
            raise urllib.error.HTTPError(request.full_url, 403, 'private content', {}, io.BytesIO(b'secret'))
        publisher = RestPublisher('https://example.invalid', 'secret-token', 'secret-key', fail)
        with self.assertRaisesRegex(RuntimeError, r'^Publish request failed \(HTTP 403\)$'):
            publisher.publish('TELANGANA', '2026-11-13', [])

    def test_https_required(self):
        with self.assertRaises(ValueError):
            RestPublisher('http://example.invalid', 'synthetic', 'synthetic')


if __name__ == '__main__':
    unittest.main()
