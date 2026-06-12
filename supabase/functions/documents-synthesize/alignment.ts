// Word-level forced alignment for lyrics-style highlighting.
//
// After TTS audio is generated and cached, this runs Sarvam batch STT with
// with_timestamps=true over the audio and stores a timings file next to it:
//   audio bucket: articles/{id}.wav          (the audio)
//                 articles/{id}.timings.json (this module's output)
//
// Output format matches the app's SentenceTiming.fromJson exactly:
//   { "words": [{"text": "...", "startMs": 0, "endMs": 430, "isWord": true}, …] }
//
// Designed to run in EdgeRuntime.waitUntil — failures are logged, never thrown:
// alignment is an enhancement; audio playback must not depend on it.
// Cost: Sarvam STT ≈ ₹30/audio-hour → ~₹0.5 per 10-minute article. One-time
// per article (cached with the audio).

const BASE = "https://api.sarvam.ai";

interface SttTimestamps {
  words: string[];
  start_time_seconds: number[];
  end_time_seconds: number[];
}

async function sarvam(path: string, key: string, body: unknown): Promise<Record<string, unknown>> {
  const r = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "api-subscription-key": key, "Content-Type": "application/json" },
    body: JSON.stringify(body ?? {}),
    signal: AbortSignal.timeout(30_000),
  });
  if (!r.ok) throw new Error(`${path} -> HTTP ${r.status}: ${(await r.text()).slice(0, 120)}`);
  return await r.json() as Record<string, unknown>;
}

async function runSttJob(wavBytes: Uint8Array, sarvamKey: string, languageCode: string): Promise<SttTimestamps | null> {
  // 1. create job
  const job = await sarvam("/speech-to-text/job/v1", sarvamKey, {
    job_parameters: {
      language_code: languageCode,
      model: "saarika:v2.5",
      with_timestamps: true,
    },
  }) as { job_id: string };

  // 2. presigned upload
  const up = await sarvam("/speech-to-text/job/v1/upload-files", sarvamKey, {
    job_id: job.job_id,
    files: ["audio.wav"],
  }) as { upload_urls: Record<string, { file_url: string; file_metadata?: Record<string, string> }> };
  const info = Object.values(up.upload_urls)[0];
  const putHeaders: Record<string, string> = { "x-ms-blob-type": "BlockBlob" };
  for (const [k, v] of Object.entries(info.file_metadata ?? {})) {
    if (typeof v === "string") putHeaders[k] = v;
  }
  const putResp = await fetch(info.file_url, { method: "PUT", body: wavBytes as BodyInit, headers: putHeaders });
  if (!putResp.ok) throw new Error(`upload PUT -> ${putResp.status}`);

  // 3. start + poll; the completed status lists the output file names
  await sarvam(`/speech-to-text/job/v1/${job.job_id}/start`, sarvamKey, {});
  let state = "";
  let outputs: string[] = [];
  for (let i = 0; i < 24; i++) {
    await new Promise((r) => setTimeout(r, 5000));
    const st = await fetch(`${BASE}/speech-to-text/job/v1/${job.job_id}/status`, {
      headers: { "api-subscription-key": sarvamKey },
    });
    const payload = await st.json() as {
      job_state?: string;
      job_details?: Array<{ outputs?: Array<{ file_name?: string }> }>;
    };
    state = payload.job_state ?? "";
    if (state === "Completed") {
      outputs = (payload.job_details ?? [])
        .flatMap((d) => d.outputs ?? [])
        .map((o) => o.file_name ?? "")
        .filter(Boolean);
      break;
    }
    if (state === "Failed" || state === "Cancelled") throw new Error(`STT job ${state}`);
  }
  if (state !== "Completed") throw new Error("STT job timed out");
  if (!outputs.length) throw new Error("STT job completed with no outputs");

  // 4. download result — NB: unlike doc-digitization, the STT job API takes
  //    download-files as a flat path with job_id + the output file names that
  //    the completed status reported (e.g. "0.json").
  const dl = await sarvam(`/speech-to-text/job/v1/download-files`, sarvamKey, {
    job_id: job.job_id,
    files: outputs,
  }) as { download_urls: Record<string, { file_url: string } | string> };
  for (const v of Object.values(dl.download_urls)) {
    const url = typeof v === "string" ? v : v.file_url;
    if (typeof url !== "string" || !url.startsWith("http")) continue;
    const resp = await fetch(url);
    if (!resp.ok) continue;
    const buf = new Uint8Array(await resp.arrayBuffer());
    let text: string;
    if (buf[0] === 0x50 && buf[1] === 0x4b) {  // "PK" — zip
      const { ZipReader, Uint8ArrayReader, TextWriter } =
        await import("https://deno.land/x/zipjs@v2.7.45/index.js");
      const zr = new ZipReader(new Uint8ArrayReader(buf));
      text = "";
      for (const entry of await zr.getEntries()) {
        if (!entry.directory && /\.json$/i.test(entry.filename)) {
          text = await entry.getData?.(new TextWriter()) as string;
          if (text) break;
        }
      }
      await zr.close();
    } else {
      text = new TextDecoder().decode(buf);
    }
    if (!text) continue;
    try {
      const parsed = JSON.parse(text) as { timestamps?: SttTimestamps };
      if (parsed.timestamps?.words?.length) return parsed.timestamps;
    } catch { /* not the json we want; try next file */ }
  }
  return null;
}

export async function alignAndStore(opts: {
  wavBytes: Uint8Array;
  articleId: string;
  languageCode: string;       // e.g. "te-IN"
  sarvamKey: string;
  // deno-lint-ignore no-explicit-any
  supabase: any;              // service-role client
}): Promise<void> {
  try {
    const ts = await runSttJob(opts.wavBytes, opts.sarvamKey, opts.languageCode);
    if (!ts) {
      console.warn("[align] no timestamps in STT result");
      return;
    }
    const words = ts.words.map((w, i) => ({
      text: w,
      startMs: Math.round((ts.start_time_seconds[i] ?? 0) * 1000),
      endMs: Math.round((ts.end_time_seconds[i] ?? 0) * 1000),
      isWord: true,
    }));
    const path = `articles/${opts.articleId}.timings.json`;
    const { error } = await opts.supabase.storage
      .from("audio")
      .upload(path, new TextEncoder().encode(JSON.stringify({ words })), {
        contentType: "application/json",
        upsert: true,
      });
    if (error) throw new Error(error.message);
    console.log(`[align] stored ${words.length} word timings -> ${path}`);
  } catch (e) {
    console.warn("[align] failed (non-fatal):", (e as Error).message);
  }
}
