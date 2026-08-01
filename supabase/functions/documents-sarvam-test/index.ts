// ONE-OFF experimental comparison, not part of the production pipeline: runs
// a given page (as a single-page PDF, base64) through the exact same Sarvam
// OCR flow documents-process-edition uses, but callable standalone so a
// half-page high-res crop can be tested directly against the whole-page
// baseline and against the Gemini holistic-read experiment.
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

const SARVAM_BASE = "https://api.sarvam.ai";

async function sarvamPost(path: string, key: string, body: unknown): Promise<Record<string, unknown>> {
  const r = await fetch(`${SARVAM_BASE}${path}`, {
    method: "POST",
    headers: { "api-subscription-key": key, "Content-Type": "application/json" },
    body: JSON.stringify(body ?? {}),
    signal: AbortSignal.timeout(30_000),
  });
  if (!r.ok) throw new Error(`${path} -> HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return await r.json() as Record<string, unknown>;
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  const CHUNK = 8192;
  let binary = "";
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, Math.min(i + CHUNK, bytes.length)));
  }
  return btoa(binary);
}

// The download is a ZIP archive (document.html/.md + metadata), not raw
// text — the earlier version of this test called .text() on it, which
// silently corrupted the binary data through UTF-8 decoding. Return it as
// base64 so the caller can unzip it properly instead.
async function ocrPageToZipBase64(pageBytes: Uint8Array, sarvamKey: string): Promise<string> {
  const job = await sarvamPost("/doc-digitization/job/v1", sarvamKey, {
    job_parameters: { language: "te-IN", output_format: "html" },
  }) as { job_id: string };

  const up = await sarvamPost("/doc-digitization/job/v1/upload-files", sarvamKey, {
    job_id: job.job_id,
    files: ["page.pdf"],
  }) as { upload_urls: Record<string, { file_url: string; file_metadata?: Record<string, string> }> };
  const info = Object.values(up.upload_urls)[0];
  const headers: Record<string, string> = { "x-ms-blob-type": "BlockBlob" };
  for (const [k, v] of Object.entries(info.file_metadata ?? {})) {
    if (typeof v === "string") headers[k] = v;
  }
  const put = await fetch(info.file_url, { method: "PUT", body: pageBytes as BodyInit, headers });
  if (!put.ok) throw new Error(`OCR upload PUT -> ${put.status}`);

  await sarvamPost(`/doc-digitization/job/v1/${job.job_id}/start`, sarvamKey, {});
  let state = "";
  for (let i = 0; i < 24; i++) {
    await new Promise((r) => setTimeout(r, 5000));
    const st = await fetch(`${SARVAM_BASE}/doc-digitization/job/v1/${job.job_id}/status`, {
      headers: { "api-subscription-key": sarvamKey },
    });
    state = ((await st.json()) as { job_state?: string }).job_state ?? "";
    if (state === "Completed") break;
    if (state === "Failed" || state === "Cancelled") throw new Error(`OCR job ${state}`);
  }
  if (state !== "Completed") throw new Error(`OCR job timed out, last state: ${state}`);

  const dl = await sarvamPost(`/doc-digitization/job/v1/${job.job_id}/download-files`, sarvamKey, {}) as {
    download_urls: Record<string, { file_url: string } | string>;
  };
  for (const v of Object.values(dl.download_urls)) {
    const url = typeof v === "string" ? v : v.file_url;
    const r = await fetch(url);
    if (r.ok) return bytesToBase64(new Uint8Array(await r.arrayBuffer()));
  }
  throw new Error("no downloadable OCR result");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const SARVAM_KEY = Deno.env.get("SARVAM_API_KEY");
  if (!SARVAM_KEY) return json({ error: "config_missing" }, 500);

  const body = await req.json().catch(() => null) as { pdfBase64?: string } | null;
  if (!body?.pdfBase64) return json({ error: "missing_pdf" }, 400);

  try {
    const bytes = base64ToBytes(body.pdfBase64);
    const zipBase64 = await ocrPageToZipBase64(bytes, SARVAM_KEY);
    return json({ ok: true, zipBase64 });
  } catch (e) {
    return json({ error: "sarvam_failed", message: (e as Error).message }, 502);
  }
});
