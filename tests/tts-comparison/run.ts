/**
 * TTS Provider Comparison Runner — GatiVani
 *
 * Runs all 5 Telugu test cases through three TTS providers and writes audio
 * files to ./output/ so you can listen and compare side-by-side.
 *
 * USAGE:
 *   deno run --allow-net --allow-env --allow-write --allow-read run.ts
 *
 * REQUIRED ENV VARS (copy .env.test.example → .env.test and fill in):
 *   SARVAM_API_KEY    — from packages/core/.env (already set)
 *   GEMINI_API_KEY    — from Google AI Studio: aistudio.google.com/app/apikey
 *
 * OUTPUT FILES:
 *   output/<caseId>_sarvam.wav
 *   output/<caseId>_gemini25.wav
 *   output/<caseId>_gemini31.wav
 *
 * After running, open the output/ folder and play each triplet to compare.
 * Focus on: test 02 (code-switch), 03 (numbers), 04 (Sarvam chunk seam), 05 (names).
 */

import { load } from "https://deno.land/std@0.224.0/dotenv/mod.ts";
import { join } from "https://deno.land/std@0.224.0/path/mod.ts";
import { TEST_CASES } from "./test-cases.ts";
import { synthesizeSarvam } from "./providers/sarvam.ts";
import { synthesizeGemini25 } from "./providers/gemini25.ts";
import { synthesizeGemini31 } from "./providers/gemini31.ts";
import type { TTSResult } from "./types.ts";

// ── Load env ─────────────────────────────────────────────────────────────────

const scriptDir = new URL(".", import.meta.url).pathname;
let env: Record<string, string> = {};
try {
  env = await load({ envPath: join(scriptDir, ".env.test") });
} catch {
  // Fall back to process env if .env.test not present
}

const SARVAM_API_KEY = env["SARVAM_API_KEY"] ?? Deno.env.get("SARVAM_API_KEY") ?? "";
const GEMINI_API_KEY = env["GEMINI_API_KEY"] ?? Deno.env.get("GEMINI_API_KEY") ?? "";

if (!SARVAM_API_KEY) { console.error("❌  SARVAM_API_KEY not set"); Deno.exit(1); }
if (!GEMINI_API_KEY) { console.error("❌  GEMINI_API_KEY not set — get one at aistudio.google.com/app/apikey"); Deno.exit(1); }

// ── Output directory ──────────────────────────────────────────────────────────

const outputDir = join(scriptDir, "output");
await Deno.mkdir(outputDir, { recursive: true });

// ── Result table ──────────────────────────────────────────────────────────────

interface Row {
  caseId: string;
  provider: string;
  latencyMs: number;
  durationSec: number;
  chunks: number;
  chars: number;
  costUsd: number;
  file: string;
  note?: string;
}

const rows: Row[] = [];

// ── Runner ────────────────────────────────────────────────────────────────────

for (const tc of TEST_CASES) {
  console.log(`\n${"─".repeat(64)}`);
  console.log(`▶  ${tc.id}  |  ${tc.label}`);
  console.log(`   Text (${tc.text.length} chars): ${tc.text.slice(0, 60)}…`);
  console.log(`   Review: ${tc.reviewNotes}`);

  const providers: Array<{
    name: string;
    fn: () => Promise<TTSResult>;
    fileSlug: string;
  }> = [
    {
      name: "Sarvam",
      fn: () => synthesizeSarvam(tc.text, SARVAM_API_KEY),
      fileSlug: "sarvam",
    },
    {
      name: "Gemini 2.5 Flash TTS",
      fn: () => synthesizeGemini25(tc.text, GEMINI_API_KEY),
      fileSlug: "gemini25",
    },
    {
      name: "Gemini 3.1 Flash TTS",
      fn: () => synthesizeGemini31(tc.text, GEMINI_API_KEY, tc.id),
      fileSlug: "gemini31",
    },
  ];

  for (const p of providers) {
    process.stdout.write(`   ${p.name.padEnd(22)} → `);
    try {
      const result = await p.fn();
      const filename = `${tc.id}_${p.fileSlug}.${result.ext}`;
      const filePath = join(outputDir, filename);
      await Deno.writeFile(filePath, result.audioBytes);

      console.log(
        `${result.durationSec}s  |  ${result.latencyMs}ms  |  $${result.estimatedCostUsd.toFixed(5)}` +
          (result.chunks > 1 ? `  |  ${result.chunks} chunks` : "") +
          (result.note ? `  |  ${result.note}` : ""),
      );

      rows.push({
        caseId: tc.id,
        provider: result.provider,
        latencyMs: result.latencyMs,
        durationSec: result.durationSec,
        chunks: result.chunks,
        chars: result.inputChars,
        costUsd: result.estimatedCostUsd,
        file: filename,
        note: result.note,
      });
    } catch (err) {
      console.log(`FAILED — ${(err as Error).message}`);
    }
  }
}

// ── Summary table ─────────────────────────────────────────────────────────────

console.log(`\n${"═".repeat(100)}`);
console.log("SUMMARY");
console.log("═".repeat(100));
console.log(
  "Case".padEnd(26) +
    "Provider".padEnd(26) +
    "Chars".padStart(6) +
    "Chunks".padStart(8) +
    "Latency".padStart(10) +
    "Duration".padStart(10) +
    "Cost USD".padStart(11),
);
console.log("─".repeat(100));

for (const r of rows) {
  console.log(
    r.caseId.padEnd(26) +
      r.provider.padEnd(26) +
      String(r.chars).padStart(6) +
      String(r.chunks).padStart(8) +
      `${r.latencyMs}ms`.padStart(10) +
      `${r.durationSec}s`.padStart(10) +
      `$${r.costUsd.toFixed(5)}`.padStart(11),
  );
}

// Per-provider totals
const providers = ["Sarvam Bulbul:v3", "Gemini 2.5 Flash TTS", "Gemini 3.1 Flash TTS"];
console.log("─".repeat(100));
for (const p of providers) {
  const pRows = rows.filter((r) => r.provider === p);
  const totalCost = pRows.reduce((s, r) => s + r.costUsd, 0);
  const avgLatency = Math.round(pRows.reduce((s, r) => s + r.latencyMs, 0) / pRows.length);
  const totalDuration = pRows.reduce((s, r) => s + r.durationSec, 0);
  console.log(
    "TOTAL".padEnd(26) +
      p.padEnd(26) +
      "".padStart(6) +
      "".padStart(8) +
      `avg ${avgLatency}ms`.padStart(10) +
      `${totalDuration}s`.padStart(10) +
      `$${totalCost.toFixed(5)}`.padStart(11),
  );
}

console.log(`\n✅  Audio files written to: ${outputDir}`);
console.log("   Open the folder and play each triplet to compare providers.");
console.log("   Recommended listening order per case:");
console.log("     01 → baseline naturalness");
console.log("     02 → code-switching English word handling");
console.log("     03 → number/date pronunciation");
console.log("     04 → Sarvam chunk seam vs Gemini single-call at 596 chars");
console.log("     05 → named entity accuracy (KCR, Hyderabad, BJP)");
