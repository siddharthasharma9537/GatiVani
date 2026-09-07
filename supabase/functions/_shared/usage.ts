// Cost ledger — writes one `model_calls` row per paid external call.
//
// Why this exists: nothing recorded what an edition cost, so every rupee figure
// in docs/ORCHESTRATION_PLAN.md is an estimate read off the code. This turns
// them into measurements. See the migration 20260903000000_model_calls.sql and
// the `edition_cost` / `tts_pool_usage` views.
//
// Two rules for callers:
//   1. Logging must never break the thing being logged. Every function here
//      swallows its own errors — a failed insert costs a console warning, not
//      a failed narration.
//   2. Log the attempt, not just the success. Failed calls are billed by some
//      providers and are always worth seeing, so pass `ok: false` rather than
//      skipping the row.

// ── Prices ───────────────────────────────────────────────────────────────────
// Rupees, as of 2026-09-02 (₹95 / $1). Kept here rather than in SQL so each row
// is stamped with the price actually in force when the call was made; changing
// a price later must not silently rewrite history.
//
// Sources and the reasoning behind each: docs/ORCHESTRATION_PLAN.md §2.1.

const INR_PER_USD = 95;

/** USD per 1M tokens, [input, output]. */
const LLM_USD_PER_MTOK: Record<string, [number, number]> = {
  "gemini-2.5-flash": [0.30, 2.50],
  "gemini-2.5-flash-lite": [0.10, 0.40],
  "gemini-flash-latest": [0.30, 2.50],
  // Successors, for when the 2.5 line retires on 16 Oct 2026 (§2.1, verify).
  "gemini-3.1-flash-lite": [0.25, 1.50],
  "gemini-3.5-flash-lite": [0.30, 2.50],
  "gemini-3.5-flash": [1.50, 9.00],
};

/**
 * Gemini TTS bills audio as output tokens at 25 tokens per second of speech.
 * USD per 1M audio tokens.
 */
const GEMINI_TTS_USD_PER_MTOK: Record<string, number> = {
  "gemini-2.5-flash-preview-tts": 10.0,
  "gemini-3.5-flash-tts": 6.0,
  "gemini-3.1-flash-tts": 20.0,
};
const GEMINI_TTS_TOKENS_PER_SECOND = 25;

/**
 * Google Cloud TTS bills per character, by voice tier, with a monthly free pool
 * per tier. The free pool is NOT modelled here: this records list price so the
 * ledger shows what the usage would cost, and `tts_pool_usage` shows how much
 * of each pool is spent. Reconcile against Cloud Billing, which applies the
 * free tier.
 */
const CLOUD_TTS_USD_PER_MCHAR: Array<[RegExp, number]> = [
  [/-Chirp3-HD-/i, 30.0],
  [/-Neural2-/i, 16.0],
  [/-Wavenet-/i, 4.0],
  [/-Standard-/i, 4.0],
];

/** Sarvam Vision document digitisation, ₹ per page (already rupees). */
const SARVAM_OCR_INR_PER_PAGE = 0.50;

function usdToPaise(usd: number): number {
  return Math.round(usd * INR_PER_USD * 100);
}

// ── Cost calculators ─────────────────────────────────────────────────────────

export function llmPaise(model: string, inputTokens: number, outputTokens: number): number {
  const price = LLM_USD_PER_MTOK[model];
  if (!price) return 0; // unknown model: record the call, don't invent a price
  const usd = (inputTokens / 1e6) * price[0] + (outputTokens / 1e6) * price[1];
  return usdToPaise(usd);
}

export function geminiTtsPaise(model: string, audioSeconds: number): number {
  const perMTok = GEMINI_TTS_USD_PER_MTOK[model];
  if (!perMTok) return 0;
  const tokens = audioSeconds * GEMINI_TTS_TOKENS_PER_SECOND;
  return usdToPaise((tokens / 1e6) * perMTok);
}

export function cloudTtsPaise(voice: string, chars: number): number {
  for (const [pattern, perMChar] of CLOUD_TTS_USD_PER_MCHAR) {
    if (pattern.test(voice)) return usdToPaise((chars / 1e6) * perMChar);
  }
  return 0;
}

export function ocrPaise(pages: number): number {
  return Math.round(pages * SARVAM_OCR_INR_PER_PAGE * 100);
}

// ── The row ──────────────────────────────────────────────────────────────────

export interface ModelCall {
  fn: string;
  kind: "llm" | "tts" | "ocr";
  provider: "gemini" | "sarvam" | "google-tts";
  model: string;
  jobId?: string | null;
  newspaperId?: string | null;
  articleId?: string | null;
  page?: number | null;
  inputTokens?: number | null;
  outputTokens?: number | null;
  chars?: number | null;
  audioSeconds?: number | null;
  pages?: number | null;
  inrPaise?: number;
  latencyMs?: number | null;
  ok?: boolean;
  error?: string | null;
}

/** A uuid or null — the DB columns are uuid-typed and reject anything else. */
function uuidOrNull(v: unknown): string | null {
  return typeof v === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v)
    ? v
    : null;
}

/**
 * Record one call. Never throws and never rejects: a logging failure must not
 * take down the request it is measuring.
 */
// deno-lint-ignore no-explicit-any
export async function logCall(supabase: any, call: ModelCall): Promise<void> {
  if (!supabase) return;
  try {
    const { error } = await supabase.from("model_calls").insert({
      fn: call.fn,
      kind: call.kind,
      provider: call.provider,
      model: call.model,
      job_id: uuidOrNull(call.jobId),
      newspaper_id: uuidOrNull(call.newspaperId),
      article_id: uuidOrNull(call.articleId),
      page: call.page ?? null,
      input_tokens: call.inputTokens ?? null,
      output_tokens: call.outputTokens ?? null,
      chars: call.chars ?? null,
      audio_seconds: call.audioSeconds ?? null,
      pages: call.pages ?? null,
      inr_paise: call.inrPaise ?? 0,
      latency_ms: call.latencyMs ?? null,
      ok: call.ok ?? true,
      error: call.error ? String(call.error).slice(0, 500) : null,
    });
    if (error) console.warn("[usage] insert failed:", error.message);
  } catch (e) {
    console.warn("[usage] insert threw:", (e as Error).message);
  }
}

/**
 * Fire-and-forget variant for hot paths that should not wait on the insert.
 * Uses EdgeRuntime.waitUntil so the write still completes after the response
 * is sent, when the runtime supports it.
 */
// deno-lint-ignore no-explicit-any
export function logCallAsync(supabase: any, call: ModelCall): void {
  const p = logCall(supabase, call);
  // deno-lint-ignore no-explicit-any
  const rt = (globalThis as any).EdgeRuntime;
  if (rt?.waitUntil) rt.waitUntil(p);
}

/**
 * Gemini returns billed token counts in `usageMetadata`. Pull them out
 * defensively — the shape has changed across API versions and a missing field
 * must not cost us the whole row.
 */
export function geminiTokens(
  json: unknown,
): { inputTokens: number; outputTokens: number } {
  // deno-lint-ignore no-explicit-any
  const u = (json as any)?.usageMetadata ?? {};
  const input = Number(u.promptTokenCount ?? 0);
  // Thinking tokens are billed as output but reported separately.
  const output = Number(u.candidatesTokenCount ?? 0) +
    Number(u.thoughtsTokenCount ?? 0);
  return {
    inputTokens: Number.isFinite(input) ? input : 0,
    outputTokens: Number.isFinite(output) ? output : 0,
  };
}
