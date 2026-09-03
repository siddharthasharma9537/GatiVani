// Shared plumbing for the edition pipeline.
//
// The pipeline is three functions over two tables:
//
//   pipeline-start     split the PDF, create the job and one row per page,
//                      then claim and fire the first k pages
//   pipeline-page      process ONE page; on finish, claim and fire the next
//   pipeline-finalize  stitch cross-page continuations, clean up, mark ready
//
// Parallelism comes from `claim_ingest_pages` handing disjoint pages to
// concurrent workers (FOR UPDATE SKIP LOCKED). Durability comes from
// `requeue_stale_ingest_pages`, run by cron, returning pages whose worker died.
// Neither is in the hot path: a healthy run never waits for cron.

import { logCall, ocrPaise } from "./usage.ts";

/** How many pages may be in flight at once for one job. */
export const CONCURRENCY = Number(Deno.env.get("INGEST_CONCURRENCY") ?? "4");

/** Retries per page before it is failed for good. Mirrors the SQL default. */
export const MAX_ATTEMPTS = 3;

export interface ClaimedPage {
  job_id: string;
  page: number;
  attempts: number;
}

/**
 * Only the service role may drive the pipeline. The page worker is a public
 * HTTP endpoint like any other function, so without this anyone could POST a
 * job id and make us process pages on demand.
 */
export function isServiceRole(req: Request): boolean {
  try {
    const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const payload = JSON.parse(
      atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")),
    );
    return payload.role === "service_role";
  } catch {
    return false;
  }
}

export function functionsBase(): string {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  return `${url}/functions/v1`;
}

/**
 * Fire another function without waiting for it.
 *
 * `EdgeRuntime.waitUntil` keeps the invocation alive long enough for the
 * request to leave, but the caller does not block on the response — that is
 * what makes pages overlap. A failure here is not fatal: the page stays
 * 'processing' and the cron sweep will requeue it, which is the whole point of
 * having the sweep.
 */
export function fireAndForget(path: string, body: unknown): void {
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const p = fetch(`${functionsBase()}/${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${serviceKey}`,
    },
    body: JSON.stringify(body),
  }).then(
    (r) => {
      if (!r.ok) console.warn(`[pipeline] ${path} -> HTTP ${r.status}`);
      return r.body?.cancel();
    },
    (e) => console.warn(`[pipeline] ${path} fire failed:`, (e as Error).message),
  );
  // deno-lint-ignore no-explicit-any
  (globalThis as any).EdgeRuntime?.waitUntil?.(p);
}

/**
 * Claim up to [limit] queued pages and start a worker for each.
 * Returns how many were started.
 */
// deno-lint-ignore no-explicit-any
export async function claimAndFire(
  supabase: any,
  jobId: string,
  limit: number = CONCURRENCY,
): Promise<number> {
  const { data, error } = await supabase.rpc("claim_ingest_pages", {
    p_job_id: jobId,
    p_limit: limit,
  });
  if (error) {
    console.warn("[pipeline] claim failed:", error.message);
    return 0;
  }
  const pages = (data ?? []) as ClaimedPage[];
  for (const p of pages) {
    fireAndForget("pipeline-page", { jobId, page: p.page, attempt: p.attempts });
  }
  return pages.length;
}

// deno-lint-ignore no-explicit-any
export async function markPage(
  supabase: any,
  jobId: string,
  page: number,
  patch: Record<string, unknown>,
): Promise<void> {
  const { error } = await supabase
    .from("ingest_pages")
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq("job_id", jobId).eq("page", page);
  if (error) console.warn("[pipeline] page update failed:", error.message);
}

// deno-lint-ignore no-explicit-any
export async function markJob(
  supabase: any,
  jobId: string,
  patch: Record<string, unknown>,
): Promise<void> {
  const { error } = await supabase
    .from("ingest_jobs")
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq("id", jobId);
  if (error) console.warn("[pipeline] job update failed:", error.message);
}

/**
 * Record a page failure, deciding whether it can be retried.
 *
 * A page returned to 'queued' will be picked up by the next claim — either the
 * sibling worker finishing its own page, or the cron sweep.
 */
// deno-lint-ignore no-explicit-any
export async function failPage(
  supabase: any,
  jobId: string,
  page: number,
  attempt: number,
  message: string,
): Promise<void> {
  const terminal = attempt >= MAX_ATTEMPTS;
  await markPage(supabase, jobId, page, {
    status: terminal ? "failed" : "queued",
    claimed_at: null,
    last_error: message.slice(0, 500),
  });
  console.warn(
    `[pipeline] job ${jobId} page ${page} attempt ${attempt} failed` +
      `${terminal ? " (giving up)" : " (will retry)"}: ${message}`,
  );
}

export interface JobCounts {
  total: number;
  terminal: number;
  done: number;
  failed: number;
  articles: number;
}

/** Where a job stands. Used to decide whether finalize should run. */
// deno-lint-ignore no-explicit-any
export async function jobCounts(supabase: any, jobId: string): Promise<JobCounts> {
  const { data } = await supabase
    .from("ingest_pages")
    .select("status, article_count")
    .eq("job_id", jobId);
  const rows = (data ?? []) as Array<{ status: string; article_count: number }>;
  const terminalStates = new Set(["done", "failed", "skipped"]);
  return {
    total: rows.length,
    terminal: rows.filter((r) => terminalStates.has(r.status)).length,
    done: rows.filter((r) => r.status === "done" || r.status === "skipped").length,
    failed: rows.filter((r) => r.status === "failed").length,
    articles: rows.reduce((n, r) => n + (r.article_count ?? 0), 0),
  };
}

/** sha256 hex — the page dedupe key, over OCR text. */
export async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Ledger row for one Sarvam OCR page. */
// deno-lint-ignore no-explicit-any
export async function logOcr(
  supabase: any,
  jobId: string,
  newspaperId: string | null,
  page: number,
  startedAt: number,
): Promise<void> {
  await logCall(supabase, {
    fn: "pipeline-page",
    kind: "ocr",
    provider: "sarvam",
    model: "sarvam-doc-digitization-v1",
    jobId,
    newspaperId,
    page,
    pages: 1,
    inrPaise: ocrPaise(1),
    latencyMs: Date.now() - startedAt,
  });
}
