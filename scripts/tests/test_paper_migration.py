"""Parse only: no database, SQL execution, or migration application."""
from pathlib import Path
import unittest

try:
    from pglast import parse_sql, parse_plpgsql
except ImportError:
    parse_sql = None

SQL = Path(__file__).resolve().parents[2] / 'supabase/migrations/20261113000000_todays_paper.sql'


class MigrationTests(unittest.TestCase):
    @unittest.skipIf(parse_sql is None, 'Install pglast for offline PostgreSQL parsing')
    def test_postgres_and_plpgsql_syntax(self):
        text = SQL.read_text()
        self.assertGreater(len(parse_sql(text)), 20)
        # pglast also parses the function bodies that SQL parsing treats as strings.
        start = text.index('create or replace function public.publish_paper_day(')
        end = text.index('end $$;', start) + len('end $$;')
        self.assertTrue(parse_plpgsql(text[start:end]))

    def test_contract_is_invoker_only_and_has_scoped_day_delete(self):
        text = SQL.read_text()
        self.assertNotIn('security definer', text.lower())
        self.assertIn('security invoker', text.lower())
        self.assertIn('pg_advisory_xact_lock', text)
        self.assertIn('on conflict (edition, source_date, source_id)', text)
        self.assertIn("where edition = 'TELANGANA' and source_date = date '2026-11-13'", text)
        self.assertIn('on delete cascade', text)
