// Vāni — GatiVani's grounded assistant.
//
// Input:  { question, articleId, articleText?, articleTitle? }
// For newspaper-edition articles (in the DB) the function derives the
// article's edition server-side and grounds on the CURRENT article (full
// text) + an INDEX of the whole edition. For content that is NOT in the DB
// (Live web stories, podcasts, GatiVani Take) the client passes the piece's
// own text via articleText, and Vāni grounds on that alone.
// It must not invent news — if something isn't in the content, it says so.
//
// Model: gemini-flash-latest (always Google's current Flash; chat quality
// matters here). TTS stays on the separate gemini-2.5-flash TTS path in
// documents-synthesize for cost.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { generate } from "../_shared/gemini.ts";

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
      { question?: string; articleId?: string; articleText?: string; articleTitle?: string; mode?: string } | null;
    const general = body?.mode === "general";
    const question = (body?.question ?? "").trim();
    const articleId = body?.articleId ?? "";
    const clientText = (body?.articleText ?? "").trim();
    const clientTitle = (body?.articleTitle ?? "").trim();
    if (!question) return json({ error: "missing_question" }, 400);
    if (!articleId && !clientText) return json({ error: "missing_article" }, 400);

    // Prefer DB grounding (edition articles get the whole edition's index);
    // fall back to the client-provided text for web stories / podcasts.
    let articleBlock = "";
    let indexBlock = "";
    // Hoisted out of the `if (articleId)` block below: the cost ledger needs
    // this client on every path, including Live articles grounded on
    // client-supplied text, which never touch the articles table.
    const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
    if (articleId) {
      const { data: article } = await supabase
        .from("articles")
        .select("title, full_content, section, newspaper_id")
        .eq("id", articleId).maybeSingle();
      if (article) {
        articleBlock =
          `${article.section} — ${article.title}\n${(article.full_content ?? "").slice(0, 6000)}`;
        const { data: edition } = await supabase
          .from("articles")
          .select("title, section, content_preview")
          .eq("newspaper_id", article.newspaper_id)
          .order("page_number");
        indexBlock = (edition ?? [])
          .map((a, i) => `${i + 1}. [${a.section}] ${a.title} — ${a.content_preview ?? ""}`)
          .join("\n")
          .slice(0, 8000);
      }
    }
    if (!articleBlock && clientText) {
      articleBlock = `${clientTitle}\n${clientText.slice(0, 8000)}`;
    }
    if (!articleBlock) return json({ error: "article_not_found" }, 404);

    // Article mode grounds strictly on the given content. General mode (the
    // floating Vāni button) is the app-wide assistant: today's content index
    // for news questions, general knowledge for everything else — but it
    // must never invent news that isn't in the index.
    const prompt = general
      ? `You are Vāni, the assistant inside GatiVani — a Telugu news app with a
Live tab (web stories), a Paper tab (today's printed edition) and a Shows tab
(podcasts). Below is an index of today's content. For questions about the news,
answer from this index only and never invent stories, facts or numbers that are
not in it — if it isn't there, say so. For general questions unrelated to the
news you may answer from general knowledge. Be concise (2–4 sentences). Reply
in the SAME language as the question (Telugu or English).

=== TODAY'S CONTENT ===
${articleBlock}

=== QUESTION ===
${question}`
      : `You are Vāni, GatiVani's reading assistant. The user is listening to Telugu news
and asks about it. Answer ONLY from the content below. Do not use outside knowledge
about current events, and never invent facts, names, numbers or quotes. If the
answer isn't in the content, say so plainly (in the user's language). Be concise
(2–4 sentences). Reply in the SAME language as the question (Telugu or English).

=== CURRENT ARTICLE ===
${articleBlock}
${indexBlock ? `\n=== TODAY'S EDITION (index of all articles) ===\n${indexBlock}\n` : ""}
=== QUESTION ===
${question}`;

    // gemini-flash-latest is an alias that tracks Google's current Flash, so
    // it survives the 2.5 retirement on its own — pinned deliberately rather
    // than tiered. Routed through the gateway for retry and cost logging.
    const { status, text } = await generate({
      tier: "fast",
      model: "gemini-flash-latest",
      parts: [{ text: prompt }],
      apiKey: GEMINI,
      json: false, // a prose answer for the reader, not JSON
      temperature: 0.2,
      maxOutputTokens: 600,
      timeoutMs: 40_000,
      ctx: { supabase, fn: "documents-ask", articleId: articleId || null },
    });
    if (status !== 200) return json({ error: "ask_failed", message: `Gemini HTTP ${status}` }, 502);
    return json({ ok: true, answer: text.trim() || "—" });
  } catch (err) {
    return json({ error: "ask_failed", message: (err as Error).message }, 500);
  }
});
