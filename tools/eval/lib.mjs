// Shared primitives for the eval harness. No dependencies beyond Node's
// built-in fetch (Node 18+).

// Longest common subsequence length -- reused from the pipeline's own
// titleOverlapMatch (documents-process-edition/index.ts) so the harness judges
// title similarity the same way the pipeline does, rather than a different
// heuristic that could disagree with it for no real reason.
export function lcsLen(a, b) {
  let prev = new Array(b.length + 1).fill(0);
  for (let i = 1; i <= a.length; i++) {
    const cur = new Array(b.length + 1).fill(0);
    for (let j = 1; j <= b.length; j++) {
      cur[j] = a[i - 1] === b[j - 1]
        ? prev[j - 1] + 1
        : Math.max(prev[j], cur[j - 1]);
    }
    prev = cur;
  }
  return prev[b.length];
}

export function titleSimilarity(a, b) {
  const n1 = (a ?? "").trim().replace(/\s+/g, " ");
  const n2 = (b ?? "").trim().replace(/\s+/g, " ");
  if (!n1 || !n2) return 0;
  if (n1 === n2) return 1;
  const [shorter, longer] = n1.length <= n2.length ? [n1, n2] : [n2, n1];
  if (longer.includes(shorter)) return 1;
  return lcsLen(shorter, longer) / shorter.length;
}

// Character Error Rate: Levenshtein distance / gold length. Only meaningful
// when `gold` is a genuine independent transcription -- see README for why
// this repo does not yet supply full-body gold text.
export function levenshtein(a, b) {
  const m = a.length, n = b.length;
  if (m === 0) return n;
  if (n === 0) return m;
  let prev = new Array(n + 1);
  for (let j = 0; j <= n; j++) prev[j] = j;
  for (let i = 1; i <= m; i++) {
    const cur = new Array(n + 1);
    cur[0] = i;
    for (let j = 1; j <= n; j++) {
      cur[j] = a[i - 1] === b[j - 1]
        ? prev[j - 1]
        : 1 + Math.min(prev[j], cur[j - 1], prev[j - 1]);
    }
    prev = cur;
  }
  return prev[n];
}

export function cer(gold, hyp) {
  if (!gold.length) return hyp.length ? 1 : 0;
  return levenshtein(gold, hyp) / gold.length;
}

function requireEnv(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing ${name}. Copy tools/eval/.env.example to tools/eval/.env ` +
      `and fill it in, or export it in your shell.`);
    process.exit(1);
  }
  return v;
}

// Pull every article + placement for a newspaper, straight from the live
// project -- the harness always scores current reality, never a stale export.
export async function fetchEdition(newspaperId) {
  const url = requireEnv("SUPABASE_URL").replace(/\/$/, "");
  const key = requireEnv("SUPABASE_ANON_KEY");
  const headers = { Authorization: `Bearer ${key}`, apikey: key };

  const artRes = await fetch(
    `${url}/rest/v1/articles?newspaper_id=eq.${newspaperId}` +
    `&select=id,title,full_content,section,page_number,processing_status,position_json`,
    { headers },
  );
  if (!artRes.ok) throw new Error(`articles fetch failed: ${artRes.status} ${await artRes.text()}`);
  const articles = await artRes.json();

  const placeRes = await fetch(
    `${url}/rest/v1/article_placements?newspaper_id=eq.${newspaperId}` +
    `&select=article_id,page_number,headline,kind`,
    { headers },
  );
  // article_placements may not exist yet on an older project -- degrade to
  // articles-only scoring rather than hard-failing the whole run.
  const placements = placeRes.ok ? await placeRes.json() : [];
  if (!placeRes.ok) {
    console.warn(`[eval] article_placements fetch failed (${placeRes.status}); ` +
      `scoring against articles.page_number only, no placement checks.`);
  }

  return { articles, placements };
}
