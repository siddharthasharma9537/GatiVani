// Scores the CURRENT live state of an edition against a hand-verified gold
// file. Run: node tools/eval/score.mjs tools/eval/ground-truth/<file>.json <newspaper_id>
//
// This does not try to declare a pipeline "perfect" or assign one score --
// it reports, per gold item, exactly what a human checking the page against
// the app would notice: is it there, is it visible, is the title right, does
// the body start where it should, and does it point at the page it actually
// continues on. That last check is the one this file's own gold data was
// built to catch (see nt-2026-07-26-p1.json's p1-flood-main entry).

import { readFileSync } from "node:fs";
import { titleSimilarity, cer } from "./lib.mjs";
import { fetchEdition } from "./lib.mjs";

const TITLE_MATCH_FLOOR = 0.55;

const [, , goldPath, newspaperId] = process.argv;
if (!goldPath || !newspaperId) {
  console.error("usage: node tools/eval/score.mjs <gold.json> <newspaper_id>");
  process.exit(1);
}

const gold = JSON.parse(readFileSync(goldPath, "utf8"));
const { articles, placements } = await fetchEdition(newspaperId);

const byId = new Map(articles.map((a) => [a.id, a]));
const placementsByArticle = new Map();
for (const p of placements) {
  const list = placementsByArticle.get(p.article_id) ?? [];
  list.push(p);
  placementsByArticle.set(p.article_id, list);
}

// Candidates for a gold item: articles whose PRIMARY placement (or bare
// page_number, if placements aren't populated) is the gold page. A headless
// commentary item (no title) is matched by body_start instead of title.
function candidatesForPage(page) {
  return articles.filter((a) => {
    const prim = (placementsByArticle.get(a.id) ?? []).find((p) => p.kind === "primary");
    return (prim ? prim.page_number : a.page_number) === page;
  });
}

function findMatch(item) {
  const cands = candidatesForPage(gold.gold_page);
  if (item.title) {
    let best = null, bestScore = 0;
    for (const c of cands) {
      const s = titleSimilarity(item.title, c.title ?? "");
      if (s > bestScore) { bestScore = s; best = c; }
    }
    if (best && bestScore >= TITLE_MATCH_FLOOR) return { article: best, how: `title (${bestScore.toFixed(2)})` };
  }
  if (item.body_start) {
    const probe = item.body_start.replace(/\s+/g, " ").trim().slice(0, 40);
    const byBody = cands.find((c) =>
      (c.full_content ?? "").replace(/\s+/g, " ").includes(probe));
    if (byBody) return { article: byBody, how: "body_start" };
  }
  return null;
}

const rows = [];
const matchedArticleIds = new Set();
for (const item of gold.items) {
  const match = findMatch(item);
  const row = { id: item.id, title: item.title ?? "(headless)" };

  if (!match) {
    row.status = "MISSING";
    rows.push(row);
    continue;
  }

  const { article, how } = match;
  matchedArticleIds.add(article.id);
  row.matched_via = how;
  row.visible = article.processing_status === "ready";
  row.status = row.visible ? "OK" : `HIDDEN (${article.processing_status})`;

  if (item.body_start) {
    const body = (article.full_content ?? "").replace(/\s+/g, " ");
    const anchor = item.body_start.replace(/\s+/g, " ").trim();
    row.body_start_ok = body.trimStart().startsWith(anchor.slice(0, 30));
  }
  if (item.page_end_anchor) {
    const body = (article.full_content ?? "").replace(/\s+/g, " ");
    const anchor = item.page_end_anchor.replace(/\s+/g, " ").trim();
    // For a lead that should CONTINUE elsewhere, this text must appear
    // mid-body (the merge kept going past it), not at the very end.
    const idx = body.indexOf(anchor.slice(0, 25));
    row.page_end_anchor_found = idx !== -1;
  }
  if (item.gold_body != null) {
    row.cer = Number(cer(item.gold_body, article.full_content ?? "").toFixed(3));
  }
  if (item.continues_on_page != null) {
    row.expected_continuation_page = item.continues_on_page;
    // Two different placement shapes both count as "this points where it
    // should," and a gold item doesn't say which one applies:
    //  - CONTINUATION: the matched row itself is the primary, and carries a
    //    second placement (kind='continuation') under its OWN article_id.
    //  - TEASER: the matched row was absorbed -- its own article_id no longer
    //    owns any placement. The teaser lives as a placement on THIS gold
    //    page, kind='teaser', headline matching this item, whose article_id
    //    points at a DIFFERENT article (the full story). An earlier version
    //    of this scorer only checked the first shape, so every teaser-style
    //    item read as "no placement found" even when teasers were working
    //    correctly -- it was checking the matched row's own id, not the
    //    target the teaser actually points at.
    const ownPlist = placementsByArticle.get(article.id) ?? [];
    const ownCont = ownPlist.find((p) =>
      p.kind === "continuation" && p.page_number === item.continues_on_page);

    let teaserTargetPage = null;
    const teaserPlacement = placements.find((p) =>
      p.page_number === gold.gold_page && p.kind === "teaser" &&
      titleSimilarity(p.headline, item.title ?? "") >= TITLE_MATCH_FLOOR);
    if (teaserPlacement) {
      const targetPrimary = placements.find((p) =>
        p.article_id === teaserPlacement.article_id && p.kind === "primary");
      teaserTargetPage = targetPrimary ? targetPrimary.page_number : null;
    }

    row.actual_continuation_page = ownCont
      ? ownCont.page_number
      : teaserTargetPage;
    row.continuation_ok = !!ownCont || teaserTargetPage === item.continues_on_page;
  }

  rows.push(row);
}

// Precision-side check: extracted articles on the gold page that no gold
// item matched. Not automatically wrong (gold coverage here is partial, see
// README) but worth listing -- an unusually high count on a page you believe
// is fully covered is a real signal.
const unclaimed = candidatesForPage(gold.gold_page).filter((a) => !matchedArticleIds.has(a.id));

console.log(`\n${gold.newspaper_title} — page ${gold.gold_page} — ${gold.items.length} gold items\n`);
for (const r of rows) {
  const bits = [];
  if ("body_start_ok" in r) bits.push(r.body_start_ok ? "body✓" : "body✗ WRONG START");
  if ("page_end_anchor_found" in r) bits.push(r.page_end_anchor_found ? "end-anchor✓" : "end-anchor✗ MISSING");
  if ("continuation_ok" in r) {
    bits.push(r.continuation_ok
      ? `→p${r.actual_continuation_page}✓`
      : `→p${r.actual_continuation_page ?? "none"}✗ EXPECTED p${r.expected_continuation_page}`);
  }
  if ("cer" in r) bits.push(`CER=${r.cer}`);
  console.log(
    `  ${r.status.padEnd(20)} ${r.title.padEnd(46)} ${r.matched_via ? `[${r.matched_via}]` : ""} ${bits.join("  ")}`,
  );
}

const missing = rows.filter((r) => r.status === "MISSING").length;
const hidden = rows.filter((r) => r.status.startsWith("HIDDEN")).length;
const badStart = rows.filter((r) => r.body_start_ok === false).length;
const badCont = rows.filter((r) => r.continuation_ok === false).length;

console.log(`\n  recall:            ${rows.length - missing}/${rows.length} gold items found`);
console.log(`  visible to app:    ${rows.length - missing - hidden}/${rows.length}`);
console.log(`  wrong body start:  ${badStart}`);
console.log(`  wrong/missing continuation target: ${badCont}`);
if (unclaimed.length) {
  console.log(`\n  ${unclaimed.length} article(s) on this page not matched to any gold item ` +
    `(may be real content outside this gold file's coverage -- see README):`);
  for (const a of unclaimed) console.log(`    - ${(a.title || "(untitled)").slice(0, 60)}`);
}
console.log();
