import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// feeds-markets — live market ticker for the marquee: Nifty 50, BSE Sensex,
// and Indian gold (₹/10g) + silver (₹/kg) derived from spot metal (USD/oz) and
// the USD/INR rate. Data from Yahoo Finance's keyless chart endpoint, fetched
// server-side (CORS + one place to swap the source). Numbers are indicative
// spot values, not jeweller retail rates.

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const [nifty, sensex, gold, silver, fx] = await Promise.all([
      quote("^NSEI"),
      quote("^BSESN"),
      quote("GC=F"),
      quote("SI=F"),
      quote("INR=X"),
    ]);

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
    // ₹ per 10g (gold) and per kg (silver), from USD/oz spot × USD/INR.
    if (gold && fx) {
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

    return json({ ok: true, items });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[feeds-markets]", err);
    return json({ error: "markets_failed", message }, 500);
  }
});
