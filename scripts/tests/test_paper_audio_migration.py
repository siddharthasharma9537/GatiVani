"""Parse and text checks only: no database, no SQL execution, no migration applied."""
from pathlib import Path
import unittest

try:
    from pglast import parse_sql
except ImportError:
    parse_sql = None

SQL = Path(__file__).resolve().parents[2] / 'supabase/migrations/20261125000000_paper_story_audio.sql'


class AudioMigrationTests(unittest.TestCase):
    @unittest.skipIf(parse_sql is None, 'Install pglast for offline PostgreSQL parsing')
    def test_postgres_syntax(self):
        self.assertGreater(len(parse_sql(SQL.read_text())), 5)

    def test_owner_only_no_public_select(self):
        text = SQL.read_text().lower()
        self.assertIn('enable row level security', text)
        self.assertIn('revoke all on public.paper_story_audio from anon, authenticated', text)
        self.assertNotIn('to anon', text)
        self.assertNotIn('using (true)', text)
        self.assertIn('for all to authenticated', text)
        self.assertIn('from public.story_publishers', text)
        self.assertIn('using (', text)
        self.assertIn('with check (', text)

    def test_stores_keys_not_urls_and_matches_contract_columns(self):
        text = SQL.read_text()
        for column in ('story_id', 'edition', 'source_date', 'rank', 'page', 'headline', 'object_key',
                       'bucket', 'content_type', 'bytes', 'sha256', 'duration_seconds', 'voice', 'model',
                       'characters', 'created_at'):
            self.assertIn('  %s ' % column, text)
        self.assertIn("content_type = 'audio/mp4'", text)
        self.assertIn('unique (edition, source_date, rank)', text)
        self.assertIn('primary key (edition, source_date, story_id)', text)


if __name__ == '__main__':
    unittest.main()
