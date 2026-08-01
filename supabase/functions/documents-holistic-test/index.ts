// ONE-OFF experimental comparison, not part of the production pipeline: sends
// a full newspaper page image directly to Gemini in a single call and asks it
// to extract every article as structured JSON — no Sarvam OCR block manifest,
// no multi-stage assignment/coherence/vision-recovery relay. Built to test
// whether a single holistic read outperforms the current fragmented pipeline
// on the same real page (motivated by the consumer Gemini app reading this
// exact page correctly where our pipeline produced two mismatched-kicker
// merges and a missing banner word).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-subscription-tier",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const PROMPT = `This is a full page of a Telugu newspaper. Read it directly and extract
EVERY distinct news article on the page — do not skip small items, kickers,
or briefs.

For each article, return:
- "title": the article's headline, in the original Telugu (or English if the
  headline itself is in English)
- "category": one of International, National, State, District, Politics,
  Editorial, Opinion, Business, Sports, Entertainment, Health, Sci-Tech,
  Education, Agriculture, Crime, Judiciary, Devotional, Trending, News
- "body": the full body text of the article, verbatim, in reading order. If
  the article is a front-page teaser/highlight box for a fuller story
  continued elsewhere, note that in "continuation" instead of guessing content
  that isn't on this page.
- "continuation": null, or a short note like "continues on page 3" if the
  page itself says so.

Do NOT merge two unrelated articles under one title. Do NOT invent a title
for one article by borrowing text from a different, unrelated item on the
page. If a decorative masthead/section-brand banner (e.g. a recurring column
name) appears above a specific story, keep it separate from that story's own
real headline rather than treating them as one title.

Return ONLY this JSON: {"articles": [{"title": "...", "category": "...", "body": "...", "continuation": null}]}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY");
  if (!GEMINI_KEY) return json({ error: "config_missing" }, 500);

  const body = await req.json().catch(() => null) as { imageBase64?: string; mimeType?: string; model?: string; listModels?: boolean } | null;

  if (body?.listModels) {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${GEMINI_KEY}&pageSize=200`);
    const d = await r.json();
    return json(d, r.status);
  }

  if (!body?.imageBase64 || !body.mimeType) {
    return json({ error: "missing_image" }, 400);
  }
  const model = body.model || "gemini-2.5-flash";
  // Newer models (3.6 Flash) always think and reject an explicit budget
  // override with 400 INVALID_ARGUMENT — only 2.5/3.5-era models accept
  // thinkingConfig at all, so only send it for those.
  const supportsThinkingOverride = /^gemini-(2\.5|3\.5)-/.test(model);

  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{
          role: "user",
          parts: [
            { inline_data: { mime_type: body.mimeType, data: body.imageBase64 } },
            { text: PROMPT },
          ],
        }],
        generationConfig: {
          maxOutputTokens: 32000,
          responseMimeType: "application/json",
          ...(supportsThinkingOverride ? { thinkingConfig: { thinkingBudget: 0 } } : {}),
        },
      }),
    },
  );

  if (!resp.ok) {
    const errText = await resp.text();
    return json({ error: "gemini_failed", status: resp.status, message: errText.slice(0, 500) }, 502);
  }
  const data = await resp.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number; totalTokenCount?: number };
  };
  const text = (data.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? "").join("");

  return json({ ok: true, model, raw: text, usageMetadata: data.usageMetadata });
});
