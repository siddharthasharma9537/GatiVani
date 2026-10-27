import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// gativani-actions — the SoHum/Vāni contract surface for GatiVani.
// (Not `vani-actions`: GatiVani and ChantTracker share the `sohum` Supabase project, and ChantTracker already owns that function name.)
// See github.com/SoHum-Digital-Services/sohum-contracts (docs/SOHUM_VANI_CONTRACT.md).
//
// GatiVani's own screens call the feeds-* functions directly. This function is the narrow,
// described surface a cross-product assistant (Vāni) and the SoHum console call instead: it
// publishes the capability manifest and exposes the public, read-only feeds as named actions,
// each returning { success, data } like the other verticals.
//
// Every action here is a read of public content (headlines, market rates, podcasts, exam
// alerts), so none needs the caller's identity and there is no write / propose-confirm flow.
// verify_jwt is off (supabase/config.toml) because the manifest must be public; the
// feeds-* functions are still called with the project's anon key.
//
// Bring-your-own-key audio (TTS, newspaper narration, Q&A) is deliberately not exposed: it
// needs the listener's own Gemini key, which never leaves their device.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function errorResponse(code: string, message_en: string, message_te: string, status = 400): Response {
  return json({ error: { code, message_en, message_te } }, status);
}

const NEWS_TOPICS = ["top", "politics", "cricket", "cinema", "weather", "national", "business"];
const NEWS_LANGS = ["te", "hi"];
const ALERT_TOPICS = [
  "jee", "neet", "eapcet", "cat", "gate", "boards",
  "upsc", "tspsc", "appsc", "ssc_jobs", "railways", "banking", "dsc",
];

// A positive integer from a query string, clamped to [1, max]; `fallback` when absent or invalid.
export function intParam(value: string | null, fallback: number, max: number): number {
  const n = parseInt(value ?? "", 10);
  return Number.isFinite(n) && n > 0 ? Math.min(n, max) : fallback;
}

type Query = Record<string, string>;
type Result = { data: unknown } | Response;

interface Action {
  description: string;
  params: Record<string, string>;
  params_schema: Record<string, unknown>;
  run: (q: URLSearchParams) => Promise<Result>;
}

// Calls a sibling feeds-* function and returns its JSON, or a contract error.
async function feed(name: string, query: Query): Promise<{ body: Record<string, unknown> } | Response> {
  const url = `${SUPABASE_URL}/functions/v1/${name}?${new URLSearchParams(query)}`;
  let res: globalThis.Response;
  try {
    res = await fetch(url, { headers: { Authorization: `Bearer ${SUPABASE_ANON_KEY}`, apikey: SUPABASE_ANON_KEY } });
  } catch {
    return errorResponse("UPSTREAM_UNAVAILABLE", "The feed is unavailable right now", "ఫీడ్ ప్రస్తుతం అందుబాటులో లేదు", 502);
  }
  if (!res.ok) {
    return errorResponse("UPSTREAM_ERROR", "The feed could not be read", "ఫీడ్ చదవలేకపోయాం", 502);
  }
  return { body: await res.json() };
}

const ACTIONS: Record<string, Action> = {
  get_headlines: {
    description: "Latest Telugu (or Hindi) news headlines for a topic, each with its source and link",
    params: {
      topic: `string (optional, default top): ${NEWS_TOPICS.join(" | ")}`,
      lang: "string (optional, default te): te | hi",
      limit: "number (optional, default 5, max 12)",
    },
    params_schema: {
      type: "object",
      properties: {
        topic: { enum: NEWS_TOPICS, default: "top" },
        lang: { enum: NEWS_LANGS, default: "te" },
        limit: { type: "integer", minimum: 1, maximum: 12, default: 5 },
      },
    },
    run: async (q) => {
      const topic = q.get("topic") ?? "top";
      const lang = q.get("lang") ?? "te";
      if (!NEWS_TOPICS.includes(topic) || !NEWS_LANGS.includes(lang)) {
        return errorResponse("BAD_PARAMS", `topic must be one of ${NEWS_TOPICS.join(", ")} and lang one of te, hi`, "topic లేదా lang చెల్లదు");
      }
      const out = await feed("feeds-news", { topic, lang, limit: String(intParam(q.get("limit"), 5, 12)) });
      return out instanceof Response ? out : { data: out.body.items ?? [] };
    },
  },
  get_market_rates: {
    description: "Today's Nifty 50, Sensex, gold and silver rates, and petrol and diesel prices when a city is given",
    params: { city: "string (optional): a city slug such as hyderabad, vijayawada, visakhapatnam" },
    params_schema: { type: "object", properties: { city: { type: "string" } } },
    run: async (q) => {
      const out = await feed("feeds-markets", q.get("city") ? { city: q.get("city")! } : {});
      return out instanceof Response ? out : { data: out.body.items ?? [] };
    },
  },
  list_podcasts: {
    description: "Telugu podcasts, All India Radio bulletins and Mann Ki Baat, with the latest episode of each and its audio link",
    params: {},
    params_schema: { type: "object", properties: {} },
    run: async () => {
      const out = await feed("feeds-podcasts", {});
      return out instanceof Response ? out : { data: out.body.items ?? [] };
    },
  },
  get_exam_alerts: {
    description: "Newest exam-result, admit-card and government-job announcements for the chosen topics",
    params: {
      topics: `string (required): comma-separated, from ${ALERT_TOPICS.join(", ")}`,
      limit: "number (optional, default 8, max 20)",
    },
    params_schema: {
      type: "object",
      required: ["topics"],
      properties: {
        topics: { type: "string", description: `comma-separated: ${ALERT_TOPICS.join(", ")}` },
        limit: { type: "integer", minimum: 1, maximum: 20, default: 8 },
      },
    },
    run: async (q) => {
      const topics = (q.get("topics") ?? "").split(",").map((t) => t.trim()).filter(Boolean);
      const unknown = topics.filter((t) => !ALERT_TOPICS.includes(t));
      if (topics.length === 0 || unknown.length > 0) {
        return errorResponse("BAD_PARAMS", `topics must be a comma-separated list from ${ALERT_TOPICS.join(", ")}`, "topics చెల్లదు");
      }
      const out = await feed("feeds-alerts", { topics: topics.join(","), limit: String(intParam(q.get("limit"), 8, 20)) });
      return out instanceof Response ? out : { data: out.body.items ?? [] };
    },
  },
};

export function buildManifest() {
  return {
    product: "gativani",
    version: "1.0",
    actions: Object.entries(ACTIONS).map(([name, a]) => ({
      name,
      kind: "read",
      description: a.description,
      method: "GET",
      path: `/gativani-actions/${name}`,
      params: a.params,
      params_schema: a.params_schema,
    })),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });

  const url = new URL(req.url);
  const route = url.pathname.replace(/^\/(functions\/v1\/)?gativani-actions\/?/, "");

  if (route === "manifest" && req.method === "GET") return json(buildManifest());

  const action = ACTIONS[route];
  if (!action || req.method !== "GET") {
    return errorResponse("NOT_FOUND", `Unknown action: ${route}`, "తెలియని చర్య", 404);
  }
  const result = await action.run(url.searchParams);
  return result instanceof Response ? result : json({ success: true, data: result.data });
});
