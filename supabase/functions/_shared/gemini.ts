// One client for every Gemini text/vision call in GatiVani.
//
// Before this, each function built its own `fetch` to generativelanguage, with
// its own retry policy, its own JSON-scraping regex and its own hardcoded model
// id. That made three things impossible: changing model without a code change,
// knowing what a call cost, and telling a transient quota error apart from a
// genuinely bad response.
//
// ── The 16 Oct 2026 deadline ────────────────────────────────────────────────
// Google retires the Gemini 2.5 line on 2026-10-16 and every model id in this
// repo is a 2.5 one. Which is why model ids live in ENVIRONMENT VARIABLES here,
// not in code: migrating is then `supabase secrets set`, not a redeploy, and
// scripts/eval_structure.ts can score a candidate model against the golden set
// without touching a single source file. Defaults stay on 2.5 so behaviour is
// unchanged until someone deliberately moves them.
//
//   GEMINI_MODEL_FAST    default gemini-2.5-flash-lite   (structuring, per page)
//   GEMINI_MODEL_STRONG  default gemini-2.5-flash        (escalation only)
//
// Verified candidates for after the retirement (docs/ORCHESTRATION_PLAN.md
// §2.1): gemini-3.1-flash-lite, gemini-3.5-flash-lite. Newer Flash releases
// exist and move quickly — score them with the eval runner, then set the env
// var. Do not guess in code.

import { geminiTokens, llmPaise, logCall, type ModelCall } from "./usage.ts";

export type Tier = "fast" | "strong";

/** Resolve a tier to a model id. Env wins; the 2.5 defaults preserve today. */
export function modelFor(tier: Tier): string {
  return tier === "strong"
    ? (Deno.env.get("GEMINI_MODEL_STRONG") || "gemini-2.5-flash")
    : (Deno.env.get("GEMINI_MODEL_FAST") || "gemini-2.5-flash-lite");
}

/** Optional cost-ledger context; see _shared/usage.ts. */
export interface UsageCtx {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  fn: string;
  jobId?: string | null;
  newspaperId?: string | null;
  articleId?: string | null;
  page?: number | null;
}

export interface GenerateOptions {
  tier: Tier;
  /**
   * Bypass tier resolution and call this exact model. Only for callers that
   * genuinely pin a model (the eval runner scoring a candidate); everything on
   * the request path should go through a tier so the October migration stays a
   * config change.
   */
  model?: string;
  parts: unknown[];
  apiKey: string;
  /** OpenAPI-subset schema. Constrains the response so JSON is valid by construction. */
  // deno-lint-ignore no-explicit-any
  schema?: any;
  maxOutputTokens?: number;
  /**
   * Thinking tokens are billed as output. Structuring is classification over a
   * manifest, not reasoning, so it runs with thinking off — which on 2.5 also
   * stops thinking from eating the output budget and truncating the JSON.
   */
  thinkingBudget?: number;
  /** Sampling temperature. Omitted means the model's default. */
  temperature?: number;
  /**
   * Ask for JSON (default). Set false for callers that want prose — the
   * cricket commentary and any other free-text generation, where forcing a
   * JSON mime type would be wrong.
   */
  json?: boolean;
  timeoutMs?: number;
  ctx?: UsageCtx;
}

export interface GenerateResult {
  status: number;
  text: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

const RETRY_WAITS_MS = [0, 15_000];

/**
 * One Gemini call, with retry on transient failures and a ledger row per
 * attempt.
 *
 * Retries only 429 (quota window) and 5xx. A 400 is a bad request and retrying
 * it just burns latency and quota to fail identically.
 */
export async function generate(opts: GenerateOptions): Promise<GenerateResult> {
  const model = opts.model ?? modelFor(opts.tier);
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${opts.apiKey}`;

  // deno-lint-ignore no-explicit-any
  const generationConfig: any = {
    maxOutputTokens: opts.maxOutputTokens ?? 32000,
    thinkingConfig: { thinkingBudget: opts.thinkingBudget ?? 0 },
  };
  if (opts.json !== false) generationConfig.responseMimeType = "application/json";
  if (opts.schema) generationConfig.responseSchema = opts.schema;
  if (opts.temperature !== undefined) generationConfig.temperature = opts.temperature;

  const log = (extra: Partial<ModelCall>, startedAt: number) => {
    if (!opts.ctx) return;
    void logCall(opts.ctx.supabase, {
      fn: opts.ctx.fn,
      kind: "llm",
      provider: "gemini",
      model,
      jobId: opts.ctx.jobId,
      newspaperId: opts.ctx.newspaperId,
      articleId: opts.ctx.articleId,
      page: opts.ctx.page,
      latencyMs: Date.now() - startedAt,
      ...extra,
    });
  };

  let lastStatus = 0;
  for (const wait of RETRY_WAITS_MS) {
    if (wait) await new Promise((r) => setTimeout(r, wait));
    const startedAt = Date.now();
    let resp: Response;
    try {
      resp = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: opts.parts }],
          generationConfig,
        }),
        signal: AbortSignal.timeout(opts.timeoutMs ?? 60_000),
      });
    } catch (e) {
      lastStatus = 0;
      log({ ok: false, error: `fetch: ${(e as Error).message}` }, startedAt);
      continue; // network/timeout — worth one more try
    }

    lastStatus = resp.status;
    if (!resp.ok) {
      await resp.body?.cancel();
      log({ ok: false, error: `HTTP ${resp.status}` }, startedAt);
      // 4xx other than 429 will fail the same way on a retry.
      if (resp.status !== 429 && resp.status < 500) break;
      continue;
    }

    const data = await resp.json() as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };
    const { inputTokens, outputTokens } = geminiTokens(data);
    log({
      inputTokens,
      outputTokens,
      inrPaise: llmPaise(model, inputTokens, outputTokens),
    }, startedAt);

    return {
      status: resp.status,
      model,
      inputTokens,
      outputTokens,
      text: (data.candidates?.[0]?.content?.parts ?? [])
        .map((p) => p.text ?? "").join(""),
    };
  }

  return { status: lastStatus, text: "", model, inputTokens: 0, outputTokens: 0 };
}

/**
 * Parse a JSON response.
 *
 * With `responseSchema` set the body should already be clean JSON, but the
 * brace-matching fallback stays for the text-only path and for any model that
 * wraps output in prose or a fence.
 */
export function parseJson<T>(text: string): T | null {
  if (!text) return null;
  try {
    return JSON.parse(text) as T;
  } catch {
    const m = text.match(/\{[\s\S]*\}/);
    if (!m) return null;
    try {
      return JSON.parse(m[0]) as T;
    } catch {
      return null;
    }
  }
}

export interface AttemptOutcome<T> {
  value: T;
  /** Empty when the result is good; otherwise what was wrong, fed back to the model. */
  error: string;
}

export interface EscalateOptions<T> extends Omit<GenerateOptions, "tier"> {
  /** Validates a parsed response. Return "" to accept, or the reason to reject. */
  check: (value: T) => string;
  /** Label for logs, e.g. "assignment". */
  label: string;
}

/**
 * Run cheap first, escalate only on a deterministic failure.
 *
 * The ladder, in order:
 *   1. fast   + document          — where almost everything should land
 *   2. fast   + document + error  — self-correction; usually a schema slip
 *   3. strong + document          — genuinely hard pages
 *   4. fast   + no document       — last resort when image quota is exhausted
 *      or the payload is too large; text-only is cheap and often still right
 *
 * This replaces a 4-config × 2-attempt cross product that existed because free
 * Gemini keys 429 constantly and each model has a separate quota bucket. That
 * ladder was quota plumbing, not a quality strategy: it would happily answer
 * from a weaker model without ever trying a stronger one. Here each rung has a
 * distinct reason to exist, and escalation is triggered by `check` failing —
 * the same validation the structuring engine already runs.
 */
export async function generateWithEscalation<T>(
  opts: EscalateOptions<T>,
): Promise<{ value: T | null; attempts: number; lastError: string }> {
  const docParts = opts.parts;
  // The document is conventionally the first part; the rest is the prompt.
  const textOnlyParts = opts.parts.length > 1 ? opts.parts.slice(1) : opts.parts;

  const rungs: Array<{ tier: Tier; parts: unknown[]; withError: boolean; note: string }> = [
    { tier: "fast", parts: docParts, withError: false, note: "fast+doc" },
    { tier: "fast", parts: docParts, withError: true, note: "fast+doc retry" },
    { tier: "strong", parts: docParts, withError: false, note: "strong+doc" },
    { tier: "fast", parts: textOnlyParts, withError: false, note: "fast text-only" },
  ];

  let lastError = "";
  let attempts = 0;

  for (const rung of rungs) {
    attempts++;
    const parts = rung.withError && lastError
      ? [...rung.parts, {
        text: `Your previous answer was rejected: ${lastError}. Return corrected JSON only.`,
      }]
      : rung.parts;

    const res = await generate({ ...opts, tier: rung.tier, parts });
    if (res.status !== 200) {
      lastError = `HTTP ${res.status}`;
      continue;
    }

    const parsed = parseJson<T>(res.text);
    if (!parsed) {
      lastError = "response was not valid JSON";
      continue;
    }

    const err = opts.check(parsed);
    if (!err) {
      console.log(`[gemini] ${opts.label} via ${rung.note} (${res.model})`);
      return { value: parsed, attempts, lastError: "" };
    }
    lastError = err;
    console.warn(`[gemini] ${opts.label} rejected at ${rung.note}: ${err}`);
  }

  return { value: null, attempts, lastError };
}
