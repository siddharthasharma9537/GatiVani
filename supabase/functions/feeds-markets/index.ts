import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// feeds-markets — live market ticker for the marquee: Nifty 50, BSE Sensex,
// and Indian gold (₹/10g) + silver (₹/kg) derived from spot metal (USD/oz) and
// the USD/INR rate. Data from Yahoo Finance's keyless chart endpoint, fetched
// server-side (CORS + one place to swap the source).
//
// ?city=<slug> (e.g. hyderabad, vijayawada, visakhapatnam) additionally
// localizes prices to the user's nearest city: petrol + diesel ₹/L and the
// city's 24K jeweller gold rate (₹/10g, replacing the generic spot value),
// parsed from GoodReturns' daily city pages. Fuel changePct is 0 — the
// client hides the arrow for it. Everything degrades to the national spot
// values when a scrape misses.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=120",
    },
  });
}

const GRAMS_PER_OZ = 31.1035;

interface Quote {
  price: number;
  prev: number;
}

async function quote(symbol: string): Promise<Quote | null> {
  try {
    const r = await fetch(
      `https://query1.finance.yahoo.com/v8/finance/chart/${
        encodeURIComponent(symbol)
      }?interval=1d&range=5d`,
      {
        headers: { "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)" },
        signal: AbortSignal.timeout(12_000),
      },
    );
    if (!r.ok) return null;
    const d = await r.json() as {
      chart?: { result?: Array<{ meta?: Record<string, number> }> };
    };
    const m = d?.chart?.result?.[0]?.meta;
    if (!m) return null;
    const price = m.regularMarketPrice;
    const prev = m.chartPreviousClose ?? m.previousClose;
    if (typeof price !== "number" || typeof prev !== "number") return null;
    return { price, prev };
  } catch {
    return null;
  }
}

function pct(cur: number, prev: number): number {
  if (!prev) return 0;
  return Math.round(((cur - prev) / prev) * 10000) / 100;
}

async function grPage(path: string): Promise<string | null> {
  try {
    const r = await fetch(`https://www.goodreturns.in/${path}`, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; GatiVani/2.0)" },
      signal: AbortSignal.timeout(12_000),
    });
    if (!r.ok) return null;
    return await r.text();
  } catch {
    return null;
  }
}

// "…, Petrol Rate Today (3rd Jul, 2026), Rs. 115.69" / "… Price is Rs. 103.82"
function fuelPrice(html: string | null, fuel: string): number | null {
  if (!html) return null;
  const dated = new RegExp(`${fuel} Rate Today \\([^)]*\\), Rs\\. ([0-9.]+)`, "i")
    .exec(html);
  const plain = new RegExp(`${fuel} Price is Rs\\. ([0-9.]+)`, "i").exec(html);
  const v = parseFloat((dated?.[1] ?? plain?.[1]) ?? "");
  return Number.isFinite(v) && v > 40 && v < 250 ? v : null;
}

// City page 24K price is ₹ per GRAM → ×10 for the ticker's ₹/10g convention.
function cityGold10g(html: string | null): number | null {
  if (!html) return null;
  const m = /24K-price">(?:₹|&#x20b9;)\s*([\d,]+)/i.exec(html);
  if (!m) return null;
  const perGram = parseInt(m[1].replace(/,/g, ""), 10);
  return Number.isFinite(perGram) && perGram > 3000 && perGram < 40000
    ? perGram * 10
    : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const city = (new URL(req.url).searchParams.get("city") ?? "")
      .toLowerCase().replace(/[^a-z-]/g, "");
    const [nifty, sensex, gold, silver, fx, petrolHtml, dieselHtml, goldHtml] =
      await Promise.all([
        quote("^NSEI"),
        quote("^BSESN"),
        quote("GC=F"),
        quote("SI=F"),
        quote("INR=X"),
        city ? grPage(`petrol-price-in-${city}.html`) : Promise.resolve(null),
        city ? grPage(`diesel-price-in-${city}.html`) : Promise.resolve(null),
        city ? grPage(`gold-rates/${city}.html`) : Promise.resolve(null),
      ]);
    const petrol = fuelPrice(petrolHtml, "Petrol");
    const diesel = fuelPrice(dieselHtml, "Diesel");
    const localGold = cityGold10g(goldHtml);

    const items: Array<
      { key: string; value: number; changePct: number }
    > = [];

    if (nifty) {
      items.push({
        key: "nifty",
        value: Math.round(nifty.price * 100) / 100,
        changePct: pct(nifty.price, nifty.prev),
      });
    }
    if (sensex) {
      items.push({
        key: "sensex",
        value: Math.round(sensex.price * 100) / 100,
        changePct: pct(sensex.price, sensex.prev),
      });
    }
    // Gold ₹/10g: the user's city jeweller rate when available, else the
    // spot value from USD/oz × USD/INR.
    if (localGold) {
      items.push({ key: "gold", value: localGold, changePct: 0 });
    } else if (gold && fx) {
      const cur = (gold.price / GRAMS_PER_OZ) * 10 * fx.price;
      const prev = (gold.prev / GRAMS_PER_OZ) * 10 * fx.prev;
      items.push({
        key: "gold",
        value: Math.round(cur),
        changePct: pct(cur, prev),
      });
    }
    if (silver && fx) {
      const cur = (silver.price / GRAMS_PER_OZ) * 1000 * fx.price;
      const prev = (silver.prev / GRAMS_PER_OZ) * 1000 * fx.prev;
      items.push({
        key: "silver",
        value: Math.round(cur),
        changePct: pct(cur, prev),
      });
    }

    if (petrol) items.push({ key: "petrol", value: petrol, changePct: 0 });
    if (diesel) items.push({ key: "diesel", value: diesel, changePct: 0 });

    return json({ ok: true, items, city: city || null });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[feeds-markets]", err);
    return json({ error: "markets_failed", message }, 500);
  }
});
