"""Owner-run publisher for a day's prepared Paper audio (Eenadu stories, owner-only).

Contract: sohum-contracts docs/PAPER_AUDIO_SHAPE.md. Reads the generator's folder
(manifest.json plus one .m4a per story), uploads each file to a PRIVATE R2 bucket through the
S3 API and upserts one row per story into public.paper_story_audio through Supabase REST.

Credentials come only from environment variables at run time, never from files or arguments:
  R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET
  SUPABASE_URL SUPABASE_ACCESS_TOKEN SUPABASE_PUBLISHABLE_KEY
--dry-run reads only local files: no network, no credentials needed. Log lines carry ids, counts
and sizes, never headlines, file paths or secrets. Standard library only.
"""
import argparse
import datetime
import hashlib
import hmac
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

EDITIONS = ('TELANGANA', 'ANDHRA-PRADESH', 'GREATER-HYDERABAD')
CONTENT_TYPE = 'audio/mp4'
ID_RE = re.compile(r'^[a-z0-9][a-z0-9_-]*$')
DATE_RE = re.compile(r'^(0[1-9]|[12][0-9]|3[01])-(0[1-9]|1[0-2])-[0-9]{4}$')
TABLE = 'paper_story_audio'


def object_key(edition, date, rank, story_id):
    return 'paper/%s/%s/%03d_%s.m4a' % (edition, date, rank, story_id)


def prefix(edition, date):
    return 'paper/%s/%s/' % (edition, date)


def iso_date(date):
    return datetime.datetime.strptime(date, '%d-%m-%Y').strftime('%Y-%m-%d')


def build_rows(audio_dir, date, edition, bucket, now=None):
    """Validate the generator folder and return (rows, skipped_ids). Reads files, no network."""
    with open(os.path.join(audio_dir, 'manifest.json'), encoding='utf-8') as f:
        manifest = json.load(f)
    created = (now or datetime.datetime.now(datetime.timezone.utc)).strftime('%Y-%m-%dT%H:%M:%SZ')
    voice, model = manifest['speaker'], manifest['model']
    rows, skipped, ranks, ids = [], [], set(), set()
    for s in manifest['stories']:
        if s.get('edition', edition) != edition:
            continue
        if s.get('status') != 'ok':
            skipped.append(s['id'])
            continue
        sid, rank = s['id'], int(s['rank'])
        if not ID_RE.match(sid) or rank < 1 or sid in ids or rank in ranks:
            raise ValueError('Invalid or duplicate story id or rank')
        ids.add(sid)
        ranks.add(rank)
        path = os.path.join(audio_dir, os.path.basename(s['file']))
        with open(path, 'rb') as f:
            data = f.read()
        if not data:
            raise ValueError('Empty audio file for story %s' % sid)
        rows.append({
            'story_id': sid, 'edition': edition, 'source_date': date, 'rank': rank,
            'page': int(s['page']), 'headline': s['headline'],
            'object_key': object_key(edition, date, rank, sid), 'bucket': bucket,
            'content_type': CONTENT_TYPE, 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest(),
            'duration_seconds': float(s['audio_seconds']), 'voice': voice, 'model': model,
            'characters': int(s['chars']), 'created_at': created, '_path': path,
        })
    rows.sort(key=lambda r: r['rank'])
    return rows, skipped


def _quote(value, safe='-_.~'):
    return urllib.parse.quote(value, safe=safe)


def sigv4_headers(method, host, path, query, headers, payload_hash, access_key, secret_key,
                  amz_date, region='auto', service='s3'):
    """AWS Signature V4. Returns the headers to send (including Authorization)."""
    h = {k.lower(): ' '.join(str(v).split()) for k, v in headers.items()}
    h['host'] = host
    h['x-amz-date'] = amz_date
    h['x-amz-content-sha256'] = payload_hash
    signed = ';'.join(sorted(h))
    canon_query = '&'.join('%s=%s' % (_quote(k), _quote(v)) for k, v in sorted(query.items()))
    canonical = '\n'.join([method, _quote(path, '-_.~/'), canon_query,
                           ''.join('%s:%s\n' % (k, h[k]) for k in sorted(h)), signed, payload_hash])
    day = amz_date[:8]
    scope = '%s/%s/%s/aws4_request' % (day, region, service)
    to_sign = '\n'.join(['AWS4-HMAC-SHA256', amz_date, scope,
                         hashlib.sha256(canonical.encode()).hexdigest()])
    key = ('AWS4' + secret_key).encode()
    for part in (day, region, service, 'aws4_request'):
        key = hmac.new(key, part.encode(), hashlib.sha256).digest()
    sig = hmac.new(key, to_sign.encode(), hashlib.sha256).hexdigest()
    out = dict(h)
    out['authorization'] = 'AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s' % (
        access_key, scope, signed, sig)
    out.pop('host')
    return out


class R2Client:
    """Minimal S3-API client for one bucket. Errors never include response bodies or headers."""

    def __init__(self, account_id, access_key, secret_key, bucket, opener=urllib.request.urlopen,
                 clock=lambda: datetime.datetime.now(datetime.timezone.utc)):
        self.host = '%s.r2.cloudflarestorage.com' % account_id
        self.access_key, self.secret_key, self.bucket = access_key, secret_key, bucket
        self.opener, self.clock = opener, clock

    def _call(self, method, key='', query=None, body=b'', headers=None, ok_missing=False):
        query = query or {}
        path = '/%s/%s' % (self.bucket, key) if key else '/%s' % self.bucket
        signed = sigv4_headers(method, self.host, path, query, headers or {},
                               hashlib.sha256(body).hexdigest(), self.access_key, self.secret_key,
                               self.clock().strftime('%Y%m%dT%H%M%SZ'))
        url = 'https://%s%s' % (self.host, _quote(path, '-_.~/'))
        if query:
            url += '?' + '&'.join('%s=%s' % (_quote(k), _quote(v)) for k, v in sorted(query.items()))
        request = urllib.request.Request(url, body if method == 'PUT' else None, signed, method=method)
        try:
            with self.opener(request, timeout=120) as response:
                return response.status, dict(response.headers), response.read()
        except urllib.error.HTTPError as error:
            status = error.code
            error.close()
            if ok_missing and status == 404:
                return 404, {}, b''
            raise RuntimeError('Storage request failed (HTTP %d)' % status) from None
        except (urllib.error.URLError, OSError):
            raise RuntimeError('Storage request failed (connection error)') from None

    def stored_sha256(self, key):
        """The sha256 recorded when the object was uploaded, or None if absent."""
        status, headers, _ = self._call('HEAD', key, ok_missing=True)
        if status == 404:
            return None
        return {k.lower(): v for k, v in headers.items()}.get('x-amz-meta-sha256')

    def put(self, key, data, sha256):
        self._call('PUT', key, body=data,
                   headers={'content-type': CONTENT_TYPE, 'x-amz-meta-sha256': sha256})

    def list_keys(self, key_prefix):
        keys, token = [], None
        while True:
            query = {'list-type': '2', 'prefix': key_prefix}
            if token:
                query['continuation-token'] = token
            _, _, body = self._call('GET', query=query)
            root = ET.fromstring(body)
            ns = {'s': root.tag.split('}')[0].strip('{')} if '}' in root.tag else {}
            find = (lambda e, n: e.findall('s:' + n, ns)) if ns else (lambda e, n: e.findall(n))
            keys += [find(c, 'Key')[0].text for c in find(root, 'Contents')]
            truncated = find(root, 'IsTruncated')
            nxt = find(root, 'NextContinuationToken')
            if truncated and truncated[0].text == 'true' and nxt:
                token = nxt[0].text
            else:
                return keys

    def delete(self, key):
        self._call('DELETE', key, ok_missing=True)


class RestRows:
    """Supabase REST for public.paper_story_audio, as the signed-in owner (RLS applies)."""

    def __init__(self, url, access_token, api_key, opener=urllib.request.urlopen):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != 'https' or not parsed.netloc or parsed.username or parsed.path not in ('', '/') or parsed.query or parsed.fragment:
            raise ValueError('SUPABASE_URL must be an HTTPS project origin')
        self.base = url.rstrip('/') + '/rest/v1/' + TABLE
        self.headers = {'Authorization': 'Bearer ' + access_token, 'apikey': api_key,
                        'Content-Type': 'application/json'}
        self.opener = opener

    def _request(self, method, query, payload=None, prefer=None):
        headers = dict(self.headers)
        if prefer:
            headers['Prefer'] = prefer
        body = None if payload is None else json.dumps(payload, ensure_ascii=False).encode('utf-8')
        url = self.base + ('?' + urllib.parse.urlencode(query) if query else '')
        request = urllib.request.Request(url, body, headers, method=method)
        try:
            with self.opener(request, timeout=60) as response:
                response.read()
        except urllib.error.HTTPError as error:
            status = error.code
            error.close()
            raise RuntimeError('Row request failed (HTTP %d)' % status) from None
        except (urllib.error.URLError, OSError):
            raise RuntimeError('Row request failed (connection error)') from None

    def upsert(self, rows):
        self._request('POST', {'on_conflict': 'edition,source_date,story_id'},
                      rows, 'resolution=merge-duplicates,return=minimal')

    def prune(self, edition, date, keep_ids):
        """Remove the day's rows whose story is no longer in the published set."""
        keep = ','.join('"%s"' % i for i in keep_ids)
        self._request('DELETE', {'edition': 'eq.' + edition, 'source_date': 'eq.' + iso_date(date),
                                 'story_id': 'not.in.(%s)' % keep})

    def delete_day(self, edition, date):
        self._request('DELETE', {'edition': 'eq.' + edition, 'source_date': 'eq.' + iso_date(date)})


def public_row(row):
    return {k: (iso_date(v) if k == 'source_date' else v) for k, v in row.items() if not k.startswith('_')}


def publish_audio_day(audio_dir, date, edition, bucket, *, dry_run=False, r2=None, rows_api=None,
                      output=print, now=None):
    rows, skipped = build_rows(audio_dir, date, edition, bucket, now)
    if not rows:
        raise ValueError('Refusing an empty publication; use --delete-day explicitly')
    total_bytes = sum(r['bytes'] for r in rows)
    output('%s %s: %d stories, %.1f minutes, %d bytes%s' % (
        edition, date, len(rows), sum(r['duration_seconds'] for r in rows) / 60, total_bytes,
        ' (dry run)' if dry_run else ''))
    for sid in skipped:
        output('  skipped (status not ok): %s' % sid)
    uploaded = unchanged = 0
    for r in rows:
        if dry_run:
            output('  would publish %03d %s (%d bytes)' % (r['rank'], r['story_id'], r['bytes']))
            continue
        with open(r['_path'], 'rb') as f:
            data = f.read()
        if hashlib.sha256(data).hexdigest() != r['sha256']:
            raise RuntimeError('File changed while publishing')
        if r2.stored_sha256(r['object_key']) == r['sha256']:
            unchanged += 1
            state = 'unchanged'
        else:
            r2.put(r['object_key'], data, r['sha256'])
            uploaded += 1
            state = 'uploaded'
        output('  %03d %s %s' % (r['rank'], r['story_id'], state))
    if dry_run:
        return
    # Files first, rows second: a row never points at a file that was never stored.
    public = [public_row(r) for r in rows]
    rows_api.upsert(public)
    rows_api.prune(edition, date, [r['story_id'] for r in rows])
    stale = set(r2.list_keys(prefix(edition, date))) - {r['object_key'] for r in rows}
    for key in sorted(stale):
        r2.delete(key)
    output('%s %s: %d uploaded, %d unchanged, %d stale files removed' % (
        edition, date, uploaded, unchanged, len(stale)))


def delete_audio_day(date, edition, *, dry_run=False, r2=None, rows_api=None, output=print):
    key_prefix = prefix(edition, date)
    if dry_run:
        output('%s %s: would delete files under the day prefix, then its rows' % (edition, date))
        return
    for key in r2.list_keys(key_prefix):
        r2.delete(key)
    if r2.list_keys(key_prefix):
        raise RuntimeError('Day prefix is not empty after deleting; rows kept')
    rows_api.delete_day(edition, date)
    output('%s %s: day deleted (files first, then rows)' % (edition, date))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--date', required=True, help='dd-mm-yyyy, the printed date')
    parser.add_argument('--edition', required=True, choices=EDITIONS)
    parser.add_argument('--audio-dir', help='The generator folder with manifest.json and the .m4a files')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--delete-day', action='store_true')
    args = parser.parse_args(argv)
    try:
        if not DATE_RE.match(args.date):
            raise ValueError('Bad date')
        iso_date(args.date)
        if not args.delete_day and not args.audio_dir:
            raise ValueError('Publishing requires --audio-dir')
        r2 = rows_api = None
        if not args.dry_run:
            env = os.environ
            r2 = R2Client(env['R2_ACCOUNT_ID'], env['R2_ACCESS_KEY_ID'], env['R2_SECRET_ACCESS_KEY'],
                          env['R2_BUCKET'])
            rows_api = RestRows(env['SUPABASE_URL'], env['SUPABASE_ACCESS_TOKEN'],
                                env['SUPABASE_PUBLISHABLE_KEY'])
        bucket = os.environ.get('R2_BUCKET', 'gativani-paper-audio')
        if args.delete_day:
            delete_audio_day(args.date, args.edition, dry_run=args.dry_run, r2=r2, rows_api=rows_api)
        else:
            publish_audio_day(args.audio_dir, args.date, args.edition, bucket,
                              dry_run=args.dry_run, r2=r2, rows_api=rows_api)
        return 0
    except (ValueError, KeyError, RuntimeError, OSError, json.JSONDecodeError):
        # Suppress exception text: paths, content and secrets must never reach a log.
        print('Publishing failed. Check arguments, the audio folder, environment and access.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
