// Grounded "ask about this edition" assistant.
//
// Input:  { question, articleId }
// The function derives the article's edition server-side, builds context from
// the CURRENT article (full text) + an INDEX of the whole edition (every
// article's title/section/preview), and answers strictly from that content.
// It must not invent news — if something isn't in the edition, it says so.
//
// Model: gemini-2.5-flash-lite (cheap; ~$0.001/query).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

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
    const GEMINI = Deno.env.get("GEMINI_API_KEY");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!GEMINI || !SUPABASE_URL || !SERVICE_KEY) return json({ error: "config_missing" }, 500);

    const body = await req.json().catch(() => null) as
      { question?: string; articleId?: string } | null;
    const question = (body?.question ?? "").trim();
    const articleId = body?.articleId ?? "";
    if (!question) return json({ error: "missing_question" }, 400);
    if (!articleId) return json({ error: "missing_article" }, 400);

    const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

    const { data: article } = await supabase
      .from("articles")
      .select("title, full_content, section, newspaper_id")
      .eq("id", articleId).maybeSingle();
    if (!article) return json({ error: "article_not_found" }, 404);

    // Edition index: title/section/preview of every article in this edition.
    const { data: edition } = await supabase
      .from("articles")
      .select("title, section, content_preview")
      .eq("newspaper_id", article.newspaper_id)
      .order("page_number");
    const index = (edition ?? [])
      .map((a, i) => `${i + 1}. [${a.section}] ${a.title} — ${a.content_preview ?? ""}`)
      .join("\n");

    const prompt =
`You are GatiVani's reading assistant. The user is listening to a Telugu newspaper
and asks about it. Answer ONLY from the content below. Do not use outside knowledge
about current events, and never invent facts, names, numbers or quotes. If the
answer isn't in the content, say so plainly (in the user's language). Be concise
(2–4 sentences). Reply in the SAME language as the question (Telugu or English).

=== CURRENT ARTICLE ===
${article.section} — ${article.title}
${(article.full_content ?? "").slice(0, 6000)}

=== TODAY'S EDITION (index of all articles) ===
${index.slice(0, 8000)}

=== QUESTION ===
${question}`;

    const r = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${GEMINI}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.2, maxOutputTokens: 600, thinkingConfig: { thinkingBudget: 0 } },
        }),
        signal: AbortSignal.timeout(40_000),
      },
    );
    if (!r.ok) return json({ error: "ask_failed", message: `Gemini HTTP ${r.status}` }, 502);
    const data = await r.json() as { candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }> };
    const answer = (data.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? "").join("").trim();
    return json({ ok: true, answer: answer || "—" });
  } catch (err) {
    return json({ error: "ask_failed", message: (err as Error).message }, 500);
  }
});
