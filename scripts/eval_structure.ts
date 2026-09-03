#!/usr/bin/env -S deno run --allow-net --allow-read --allow-env
//
// Score a Gemini model on real newspaper pages before trusting it in production.
//
// Why this exists: Google retires the Gemini 2.5 line on 16 Oct 2026 and every
// model id in GatiVani is a 2.5 one. Picking the replacement by reading a
// pricing page is guessing — the thing that matters is whether a candidate
// extracts the same articles from a Telugu broadsheet, and what it costs to do
// so. This runs the real extraction engine against pages whose correct output
// is known, and prints accuracy next to rupees per page.
//
// ── Usage ───────────────────────────────────────────────────────────────────
//
//   export GEMINI_API_KEY=...
//   deno run --allow-net --allow-read --allow-env scripts/eval_structure.ts \
//     --fixtures eval/pages \
//     --models gemini-2.5-flash-lite,gemini-3.1-flash-lite,gemini-3.5-flash-lite
//
// Add --json to emit machine-readable results instead of a table.
//
// ── Fixtures ────────────────────────────────────────────────────────────────
// One directory per page, each containing:
//
//   page.pdf          the single page, exactly as the pipeline would send it
//   ocr.html          Sarvam's output for that page (so runs are deterministic
//                     and cost nothing in OCR — capture it once)
//   expected.json     { "articles": [ { "title": "…" }, … ] }
//
// `expected.json` needs only headlines. Judging body text by string equality
// punishes harmless whitespace differences and misses the failure that
// actually matters: articles fused together, split apart, or dropped. Headline
// set + count catches all three.
//
// Seed it from the page validated during the engine rewrite (15 correct
// articles vs 4 from the legacy parser) and grow it with any page that has
// misbehaved in production — a regression suite of real failures is worth more
// than a large synthetic one.

import { extractArticlesStructured } from "../supabase/functions/_shared/structure.ts";
import { llmPaise } from "../supabase/functions/_shared/usage.ts";

interface Expected {
  articles: Array<{ title: string }>;
}

interface PageScore {
  page: string;
  model: string;
  expectedCount: number;
  gotCount: number;
  matched: number;
  missing: string[];
  spurious: string[];
  flagged: number;
  inrPaise: number;
  ms: number;
  error?: string;
}

function arg(name: string, fallback = ""): string {
  const i = Deno.args.indexOf(`--${name}`);
  return i >= 0 && Deno.args[i + 1] ? Deno.args[i + 1] : fallback;
}
const hasFlag = (name: string) => Deno.args.includes(`--${name}`);

/** Loose headline comparison: whitespace and punctuation are not the signal. */
function normalise(s: string): string {
  return s.replace(/\s+/g, " ").replace(/[।॥.,:;!?"'`()\[\]-]/g, "").trim().toLowerCase();
}

/**
 * Count how many expected headlines were found, allowing a containment match
 * in either direction — continuation pages legitimately shorten a headline,
 * and the engine may keep a kicker the fixture omits.
 */
function matchTitles(expected: string[], got: string[]): {
  matched: number;
  missing: string[];
  spurious: string[];
} {
  const remaining = got.map(normalise);
  const missing: string[] = [];
  let matched = 0;

  for (const e of expected) {
    const n = normalise(e);
    if (!n) continue;
    const idx = remaining.findIndex((g) =>
      g === n || (g.length > 8 && n.length > 8 && (g.includes(n) || n.includes(g)))
    );
    if (idx >= 0) {
      matched++;
      remaining.splice(idx, 1);
    } else {
      missing.push(e);
    }
  }
  return { matched, missing, spurious: remaining };
}

/**
 * A ledger that records into memory instead of Postgres, so the eval can price
 * each run without a database. Matches the shape `UsageCtx.supabase` needs.
 */
function collectingLedger() {
  const rows: Array<Record<string, unknown>> = [];
  return {
    rows,
    client: {
      from() {
        return {
          insert(row: Record<string, unknown>) {
            rows.push(row);
            return Promise.resolve({ error: null });
          },
        };
      },
    },
    paise() {
      return rows.reduce((n, r) => n + Number(r.inr_paise ?? 0), 0);
    },
    reset() {
      rows.length = 0;
    },
  };
}

async function scorePage(
  dir: string,
  model: string,
  apiKey: string,
): Promise<PageScore> {
  const name = dir.split("/").filter(Boolean).pop() ?? dir;
  const expected: Expected = JSON.parse(await Deno.readTextFile(`${dir}/expected.json`));
  const html = await Deno.readTextFile(`${dir}/ocr.html`);
  const pdf = await Deno.readFile(`${dir}/page.pdf`);

  const ledger = collectingLedger();
  const startedAt = Date.now();

  // Both tiers are pinned to the candidate: this measures the model, not the
  // escalation policy. Escalation is scored separately by comparing a run's
  // `attempts` against a baseline.
  Deno.env.set("GEMINI_MODEL_FAST", model);
  Deno.env.set("GEMINI_MODEL_STRONG", model);

  try {
    const result = await extractArticlesStructured(html, pdf, "application/pdf", apiKey, {
      supabase: ledger.client,
      fn: "eval_structure",
    });
    const got = result.articles.map((a) => a.title);
    const { matched, missing, spurious } = matchTitles(
      expected.articles.map((a) => a.title),
      got,
    );
    return {
      page: name,
      model,
      expectedCount: expected.articles.length,
      gotCount: got.length,
      matched,
      missing,
      spurious,
      flagged: result.flaggedCount,
      inrPaise: ledger.paise(),
      ms: Date.now() - startedAt,
    };
  } catch (e) {
    return {
      page: name,
      model,
      expectedCount: expected.articles.length,
      gotCount: 0,
      matched: 0,
      missing: expected.articles.map((a) => a.title),
      spurious: [],
      flagged: 0,
      inrPaise: ledger.paise(),
      ms: Date.now() - startedAt,
      error: (e as Error).message,
    };
  }
}

function pct(n: number, d: number): string {
  return d === 0 ? "—" : `${((n / d) * 100).toFixed(0)}%`;
}

async function main() {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    console.error("GEMINI_API_KEY is required.");
    Deno.exit(2);
  }

  const fixturesDir = arg("fixtures", "eval/pages");
  const models = arg("models", "gemini-2.5-flash-lite").split(",").map((m) => m.trim())
    .filter(Boolean);

  const pages: string[] = [];
  for await (const entry of Deno.readDir(fixturesDir)) {
    if (entry.isDirectory) pages.push(`${fixturesDir}/${entry.name}`);
  }
  pages.sort();

  if (!pages.length) {
    console.error(
      `No fixture directories under ${fixturesDir}. Each needs page.pdf, ocr.html and expected.json — see the header of this file.`,
    );
    Deno.exit(2);
  }

  console.error(
    `Scoring ${models.length} model(s) on ${pages.length} page(s). This calls the real API and costs real money.\n`,
  );

  const all: PageScore[] = [];
  for (const model of models) {
    for (const dir of pages) {
      const score = await scorePage(dir, model, apiKey);
      all.push(score);
      if (score.error) console.error(`  ${model} / ${score.page}: ERROR ${score.error}`);
    }
  }

  if (hasFlag("json")) {
    console.log(JSON.stringify(all, null, 2));
    return;
  }

  // Per-model rollup — the table the decision is actually made from.
  console.log("model                     pages  recall  precision  flagged  ₹/page  s/page");
  console.log("─".repeat(80));
  for (const model of models) {
    const rows = all.filter((r) => r.model === model);
    const expected = rows.reduce((n, r) => n + r.expectedCount, 0);
    const got = rows.reduce((n, r) => n + r.gotCount, 0);
    const matched = rows.reduce((n, r) => n + r.matched, 0);
    const flagged = rows.reduce((n, r) => n + r.flagged, 0);
    const paise = rows.reduce((n, r) => n + r.inrPaise, 0);
    const ms = rows.reduce((n, r) => n + r.ms, 0);
    console.log(
      `${model.padEnd(25)} ${String(rows.length).padStart(5)}  ` +
        `${pct(matched, expected).padStart(6)}  ${pct(matched, got).padStart(9)}  ` +
        `${String(flagged).padStart(7)}  ` +
        `${(paise / 100 / rows.length).toFixed(3).padStart(6)}  ` +
        `${(ms / 1000 / rows.length).toFixed(1).padStart(6)}`,
    );
  }

  // Then the detail that explains a bad number.
  const problems = all.filter((r) => r.missing.length || r.spurious.length || r.error);
  if (problems.length) {
    console.log("\nPages that did not match:");
    for (const p of problems) {
      console.log(`\n  ${p.model} / ${p.page}  (expected ${p.expectedCount}, got ${p.gotCount})`);
      if (p.error) console.log(`    error: ${p.error}`);
      for (const m of p.missing.slice(0, 5)) console.log(`    missing:  ${m.slice(0, 70)}`);
      for (const s of p.spurious.slice(0, 5)) console.log(`    spurious: ${s.slice(0, 70)}`);
    }
  }

  console.log(
    "\nRecall is the number that matters: a missing article is a story the reader never hears.\n" +
      "Ship the cheapest model whose recall matches the 2.5 baseline, not the cheapest overall.",
  );
}

if (import.meta.main) await main();
