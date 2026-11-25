"""Owner-run text publisher. No credentials or publisher content are saved.

Uses Store.paper directly, never the local HTTP server. Dates on the CLI/REST
are ISO; Store's manifest dates are dd-mm-yyyy. --dry-run never creates an HTTP
client and requires an existing review state directory so even mkdir is avoided.
"""
import argparse
import collections
import datetime
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

SECTIONS = {
    'Front page': 'front', 'Editorial': 'editorial', 'Business': 'business',
    'Entertainment': 'cinema', 'Champion': 'sports', 'Vasundhara': 'vasundhara',
    'Pratibha': 'pratibha', 'Chaduvu': 'chaduvu', 'Regional': 'regional',
    'National': 'national', 'Back page': 'back', 'News': 'general',
}
SECTION_TITLES = dict(zip(SECTIONS.values(), [
    'Front page', 'Editorial news', 'Business', 'Cinema', 'Champion (sports)',
    'Vasundhara', 'Pratibha', 'Chaduvu', 'Regional', 'National', 'Back page', 'General news',
]))
ROLES = {'headline', 'kicker', 'deck', 'byline', 'subheading', 'body', 'caption', 'side'}


def rows_from_paper(paper):
    """Preserve reviewed text/narration; never reconstruct narration from display."""
    rows, seen = [], set()
    for section in paper['sections']:
        section_id = SECTIONS[section['name']]
        for story in section['stories']:
            if story['id'] in seen:
                raise ValueError('Duplicate story identity')
            seen.add(story['id'])
            items = []
            for item in story['items']:
                role = {'subhead': 'subheading', 'sidebar': 'side'}.get(item['role'], item['role'])
                if role == 'marker':
                    continue  # Continuation status is kept separately, never spoken.
                if role not in ROLES:
                    raise ValueError('Unsupported item role')
                items.append({'role': role, 'text': item['text']})
            headline = story['headline'].strip()
            # Store keeps these two roles separately from its ordered items.
            for role, text in reversed([('headline', headline), ('kicker', story.get('kicker', ''))]):
                if text and not any(i['role'] == role and i['text'] == text for i in items):
                    items.insert(0, {'role': role, 'text': text})
            cont = story.get('contTo', [])
            pages = sorted({story['page'], *(c['page'] for c in cont if c.get('linked'))})
            rows.append({
                'source_id': story['id'], 'section': section_id, 'sort_order': len(rows),
                'headline': headline, 'headline_is_graphic': bool(story.get('graphic')),
                # Local crops are never exposed as public URLs or uploaded here.
                'headline_image_url': None,
                'byline': '\n'.join(i['text'] for i in items if i['role'] == 'byline'),
                'items': items, 'display_text': '\n\n'.join(i['text'] for i in items),
                'narration_text': story['narration'].strip(), 'page_numbers': pages,
                'continuation_info': cont, 'word_count': story['words'],
            })
    return rows


class RestPublisher:
    def __init__(self, url, access_token, api_key, opener=urllib.request.urlopen):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != 'https' or not parsed.netloc or parsed.username or parsed.path not in ('', '/') or parsed.query or parsed.fragment:
            raise ValueError('SUPABASE_URL must be an HTTPS project origin')
        self.base = url.rstrip('/') + '/rest/v1/'
        self.headers = {'Authorization': 'Bearer ' + access_token, 'apikey': api_key,
                        'Content-Type': 'application/json'}
        self.opener = opener

    def _request(self, path, method, payload=None):
        body = None if payload is None else json.dumps(payload, ensure_ascii=False).encode('utf-8')
        request = urllib.request.Request(self.base + path, body, self.headers, method=method)
        try:
            with self.opener(request, timeout=60) as response:
                response.read()
        except urllib.error.HTTPError as error:
            # Do not log response bodies, request headers, credentials or content.
            status = error.code
            error.close()
            raise RuntimeError('Publish request failed (HTTP %d)' % status) from None
        except (urllib.error.URLError, OSError):
            raise RuntimeError('Publish request failed (connection error)') from None

    def publish(self, edition, date, rows):
        self._request('rpc/publish_paper_day', 'POST',
                      {'p_edition': edition, 'p_date': date, 'p_stories': rows})

    def delete(self, edition, date):
        query = urllib.parse.urlencode({'edition': 'eq.' + edition, 'source_date': 'eq.' + date})
        self._request('paper_days?' + query, 'DELETE')


def publish_day(store, date, editions, *, dry_run=False, delete_day=False, publisher=None, output=print):
    local_date = datetime.date.fromisoformat(date).strftime('%d-%m-%Y')
    if delete_day:
        for edition in editions:
            output('%s %s: %s' % (edition, date, 'would delete day' if dry_run else 'deleting day'))
            if not dry_run:
                publisher.delete(edition, date)
        return
    available = {(e['edition'], e['date']) for e in store.editions()}
    # Validate and prepare every selected edition before any network writes.
    prepared = []
    for edition in editions:
        if (edition, local_date) not in available:
            raise ValueError('Requested edition/date is unavailable locally')
        rows = rows_from_paper(store.paper(edition, local_date))
        if not rows:
            raise ValueError('Refusing an empty publication; use --delete-day explicitly')
        prepared.append((edition, rows))
    for edition, rows in prepared:
        output('%s %s: %d stories%s' % (edition, date, len(rows), ' (dry run)' if dry_run else ''))
        counts = collections.Counter(r['section'] for r in rows)
        for section, title in SECTION_TITLES.items():
            output('  %s: %d' % (title, counts[section]))
        if not dry_run:
            publisher.publish(edition, date, rows)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--date', required=True, help='ISO date YYYY-MM-DD')
    parser.add_argument('--editions', nargs='+', required=True,
                        choices=['TELANGANA', 'ANDHRA-PRADESH', 'GREATER-HYDERABAD'])
    parser.add_argument('--drive')
    parser.add_argument('--font-dir')
    parser.add_argument('--glyph-dir')
    parser.add_argument('--state-dir')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--delete-day', action='store_true')
    args = parser.parse_args(argv)
    try:
        datetime.date.fromisoformat(args.date)
        publisher = None
        if not args.dry_run:
            publisher = RestPublisher(os.environ['SUPABASE_URL'], os.environ['SUPABASE_ACCESS_TOKEN'],
                                      os.environ['SUPABASE_PUBLISHABLE_KEY'])
        store = None
        if not args.delete_day:
            if not all([args.drive, args.font_dir, args.glyph_dir, args.state_dir]):
                raise ValueError('Publishing requires --drive, --font-dir, --glyph-dir and --state-dir')
            if not os.path.isdir(os.path.join(args.state_dir, 'images')):
                raise ValueError('Use an existing local review state directory containing images/')
            sys.dont_write_bytecode = True  # Store/fonts imports must not write caches in dry runs.
            from eenadu_review_server import Store
            store = Store(args.drive, args.font_dir, args.glyph_dir, args.state_dir)
        publish_day(store, args.date, list(dict.fromkeys(args.editions)), dry_run=args.dry_run,
                    delete_day=args.delete_day, publisher=publisher)
        return 0
    except (ValueError, KeyError, RuntimeError, ImportError, OSError):
        # Intentionally suppress exception text: local paths/content and secrets
        # from a dependency's error must never end up in a publishing log.
        print('Publishing failed. Check arguments, local review files, environment and publisher access.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
