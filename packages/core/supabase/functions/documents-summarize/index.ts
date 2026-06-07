import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY");
    if (!GEMINI_KEY) {
      return json({ error: "config_missing", message: "GEMINI_API_KEY not configured" }, 500);
    }

    const body = await req.json().catch(() => null);
    if (!body?.text) return json({ error: "missing_text" }, 400);

    // Trim to ~3000 chars to keep latency and cost low
    const text = (body.text as string).trim().slice(0, 3000);

    const prompt = `You are summarizing a Telugu news article. Extract exactly 3 key facts or important points from the article as complete, meaningful Telugu sentences.

Rules:
- Each point must be a full Telugu sentence
- Each point must be factually present in the article (no hallucination)
- Do not repeat the same point twice
- Return ONLY a valid JSON array of exactly 3 strings, nothing else

Article:
${text}`;

    const resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=${GEMINI_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            responseMimeType: "application/json",
            temperature: 0.1,
            maxOutputTokens: 512,
          },
        }),
      },
    );

    if (!resp.ok) {
      const errText = await resp.text();
      throw new Error(`Gemini HTTP ${resp.status}: ${errText.slice(0, 200)}`);
    }

    const data = await resp.json() as {
      candidates?: Array<{
        content?: { parts?: Array<{ text?: string }> };
      }>;
    };

    const raw = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "[]";
    console.log(`[summarize] raw response: ${raw.slice(0, 200)}`);

    let bullets: string[] = [];
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        bullets = parsed
          .map((b: unknown) => String(b).trim())
          .filter((b) => b.length > 5)
          .slice(0, 3);
      }
    } catch {
      console.warn("[summarize] JSON parse failed, returning empty bullets");
    }

    return json({ ok: true, bullets });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[documents-summarize]", err);
    return json({ error: "summary_failed", message }, 500);
  }
});
