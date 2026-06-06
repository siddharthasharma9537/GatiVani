/**
 * TTS Quality Comparison: Sarvam Bulbul v2 vs Bhashini IndicTTS (Telugu)
 *
 * Usage:
 *   SARVAM_KEY=sk_xxx node scripts/compare-tts.mjs
 *   SARVAM_KEY=sk_xxx BHASHINI_KEY=xxx BHASHINI_USER_ID=yyy node scripts/compare-tts.mjs
 *
 * Outputs:
 *   ./sarvam_v2.wav      ← open in QuickTime / VLC
 *   ./bhashini_te.wav    ← open in QuickTime / VLC
 *
 * Bhashini free API key:  https://bhashini.gov.in/ulca/user  (register, ~2 min)
 */

import { writeFile } from "fs/promises";
import { performance } from "perf_hooks";

// ── Config ───────────────────────────────────────────────────────────────────
const SARVAM_KEY      = process.env.SARVAM_KEY      || process.env.SARVAM_API_KEY;
const BHASHINI_KEY    = process.env.BHASHINI_KEY;      // ulcaApiKey
const BHASHINI_USER   = process.env.BHASHINI_USER_ID;  // userId

// Real Telugu news text (~300 chars, realistic sample)
const TEST_TEXT = `హైదరాబాద్: ఆంధ్రప్రదేశ్ ప్రభుత్వం నీటి సంరక్షణ కోసం కొత్త పథకాన్ని ప్రారంభించింది. ముఖ్యమంత్రి ఈ కార్యక్రమాన్ని విజయవాడలో శుభారంభం చేశారు. గ్రామాల్లో చెరువులు, కుంటలు పునరుద్ధరించేందుకు రాష్ట్ర ప్రభుత్వం వేలాది కోట్ల రూపాయలు కేటాయించింది.`;

// ── Helpers ───────────────────────────────────────────────────────────────────
function b64ToBuffer(b64) {
  return Buffer.from(b64, "base64");
}

function fmt(ms) { return `${Math.round(ms)}ms`; }
function kb(bytes) { return `${(bytes / 1024).toFixed(0)} KB`; }
function dur(wavBytes) {
  // WAV: 44-byte header, then PCM at given sample rate
  // rough estimate assuming 16-bit mono
  const samples = (wavBytes - 44) / 2;
  const seconds = samples / 22050;
  return `~${seconds.toFixed(1)}s audio`;
}

// ── Sarvam Bulbul v2 ─────────────────────────────────────────────────────────
async function testSarvam() {
  if (!SARVAM_KEY) { console.log("⚠️  SARVAM_KEY not set — skipping Sarvam"); return null; }

  console.log("\n🔵 Sarvam Bulbul v2 (Telugu, male: shubh) …");
  const t0 = performance.now();

  const resp = await fetch("https://api.sarvam.ai/text-to-speech", {
    method: "POST",
    headers: { "api-subscription-key": SARVAM_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({
      inputs: [TEST_TEXT],
      target_language_code: "te-IN",
      speaker: "shubh",
      model: "bulbul:v2",
      pace: 1.0,
      speech_sample_rate: 22050,
      enable_preprocessing: true,
    }),
  });

  const elapsed = performance.now() - t0;
  const body = await resp.json();

  const audioB64 = body.audios?.[0];
  if (!audioB64) { console.log("  ❌ Failed:", JSON.stringify(body).slice(0, 200)); return null; }

  const buf = b64ToBuffer(audioB64);
  await writeFile("sarvam_v2.wav", buf);
  console.log(`  ✅  ${fmt(elapsed)} | ${kb(buf.length)} | ${dur(buf.length)}`);
  console.log(`  📁  Saved → sarvam_v2.wav`);
  return { ms: elapsed, bytes: buf.length };
}

// ── Bhashini IndicTTS ─────────────────────────────────────────────────────────
async function testBhashini() {
  if (!BHASHINI_KEY || !BHASHINI_USER) {
    console.log("\n⚠️  Bhashini credentials not set — skipping.");
    console.log("    Register free at: https://bhashini.gov.in/ulca/user");
    console.log("    Then run:");
    console.log("    SARVAM_KEY=... BHASHINI_KEY=<ulcaApiKey> BHASHINI_USER_ID=<userId> node scripts/compare-tts.mjs");
    return null;
  }

  // Step 1: Discover available Telugu TTS models
  console.log("\n🟢 Bhashini IndicTTS (Telugu) — discovering models …");
  let serviceId = "ai4bharat/indic-tts-coqui-te-gpu--t4"; // known good default

  try {
    const configResp = await fetch(
      "https://meity-auth.ulcacontrib.org/ulca/apis/v0/model/getModelsPipeline",
      {
        method: "POST",
        headers: { ulcaApiKey: BHASHINI_KEY, userID: BHASHINI_USER, "Content-Type": "application/json" },
        body: JSON.stringify({
          pipelineTasks: [{ taskType: "tts", config: { language: { sourceLanguage: "te" } } }],
          pipelineRequestConfig: { pipelineId: "64392f96daac500b55c543cd" },
        }),
      }
    );
    const configData = await configResp.json();
    const firstModel = configData?.pipelineResponseConfig?.[0]?.config?.[0];
    if (firstModel?.serviceId) {
      serviceId = firstModel.serviceId;
      console.log(`  📋  Model discovered: ${serviceId}`);
    } else {
      console.log(`  📋  Using default model: ${serviceId}`);
    }
  } catch (e) {
    console.log(`  ⚠️  Model discovery failed (${e.message}), using default: ${serviceId}`);
  }

  // Step 2: Infer
  const t0 = performance.now();

  const inferResp = await fetch(
    "https://dhruva-api.bhashini.gov.in/services/inference/pipeline",
    {
      method: "POST",
      headers: { Authorization: BHASHINI_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        pipelineTasks: [{
          taskType: "tts",
          config: { language: { sourceLanguage: "te" }, serviceId, gender: "male" },
        }],
        inputData: {
          input: [{ source: TEST_TEXT }],
          audio: [{ audioContent: null }],
        },
      }),
    }
  );

  const elapsed = performance.now() - t0;
  const body = await inferResp.json();
  const audioB64 = body.pipelineResponse?.[0]?.audio?.[0]?.audioContent;

  if (!audioB64) {
    console.log("  ❌ Failed:", JSON.stringify(body).slice(0, 400));
    return null;
  }

  const buf = b64ToBuffer(audioB64);
  await writeFile("bhashini_te.wav", buf);
  console.log(`  ✅  ${fmt(elapsed)} | ${kb(buf.length)} | ${dur(buf.length)}`);
  console.log(`  📁  Saved → bhashini_te.wav`);
  return { ms: elapsed, bytes: buf.length };
}

// ── Main ──────────────────────────────────────────────────────────────────────
console.log("━━━ Telugu TTS Comparison ━━━");
console.log(`Text (${TEST_TEXT.length} chars):\n"${TEST_TEXT.slice(0, 80)}…"`);

const [sarvam, bhashini] = await Promise.allSettled([testSarvam(), testBhashini()]);

console.log("\n━━━ Summary ━━━");
const s = sarvam.value;
const b = bhashini.value;

if (s && b) {
  console.log(`\n  Sarvam v2:  ${fmt(s.ms)} response | ${kb(s.bytes)} file`);
  console.log(`  Bhashini:   ${fmt(b.ms)} response | ${kb(b.bytes)} file`);
  const faster = s.ms < b.ms ? "Sarvam" : "Bhashini";
  const speedRatio = Math.max(s.ms, b.ms) / Math.min(s.ms, b.ms);
  console.log(`\n  ⚡ ${faster} was ${speedRatio.toFixed(1)}x faster`);
  console.log(`\n  👂 Listen and compare:`);
  console.log(`     open sarvam_v2.wav   # QuickTime on Mac`);
  console.log(`     open bhashini_te.wav`);
} else if (s) {
  console.log("  Only Sarvam ran — add Bhashini credentials to compare.");
  console.log("  open sarvam_v2.wav");
} else if (b) {
  console.log("  Only Bhashini ran — add SARVAM_KEY to compare.");
  console.log("  open bhashini_te.wav");
} else {
  console.log("  Both failed. Check API keys.");
}

console.log("\n  📊 Cost comparison for 30 min audio/day × 30 days (~540K chars/month):");
console.log("     Sarvam v2:  ₹15 × 54  = ₹810/month per user");
console.log("     Bhashini:   ₹0         = ₹0/month (govt initiative)");
console.log("     Sarvam v3:  ₹30 × 54  = ₹1,620/month per user\n");
