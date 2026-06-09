/**
 * TTS Provider Comparison Runner — GatiVani (Node.js)
 *
 * Runs 5 Telugu test cases through Sarvam Bulbul:v3, Gemini 2.5 Flash TTS,
 * and Gemini 3.1 Flash TTS. Writes .wav files to ./output/ for listening.
 *
 * RUN:  node run.mjs
 */

import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { config } from "dotenv";
import { SarvamAIClient } from "sarvamai";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Load env ──────────────────────────────────────────────────────────────────
config({ path: join(__dirname, ".env.test") });

const SARVAM_KEY = process.env.SARVAM_API_KEY ?? "";
const GEMINI_KEY = process.env.GEMINI_API_KEY ?? "";

if (!SARVAM_KEY) { console.error("❌  SARVAM_API_KEY not set in .env.test"); process.exit(1); }
if (!GEMINI_KEY) { console.error("❌  GEMINI_API_KEY not set in .env.test"); process.exit(1); }

// ── Voice config — change these to compare different voices ──────────────────
//
// Gemini 2.5 & 3.1 voices (30 total, astronomical names):
//   Warm/melodic  : Aoede, Leda, Callirrhoe
//   Clear/neutral : Kore, Puck, Zephyr
//   Deep/formal   : Charon, Fenrir, Enceladus
//   Full list     : Achernar, Achird, Algenib, Algieba, Alnilam, Aoede,
//                   Autonoe, Callirrhoe, Charon, Despina, Enceladus, Erinome,
//                   Fenrir, Gacrux, Iapetus, Kore, Laomedeia, Leda, Orus,
//                   Pulcherrima, Puck, Rasalgethi, Sadachbia, Sadaltager,
//                   Schedar, Sulafat, Umbriel, Vindemiatrix, Zephyr, Zubenelgenubi
//
// Sarvam Bulbul:v3 Telugu voices:
//   Female (te-IN default): priya, neha, pooja, kavya, ishita, shreya,
//                           roopa, tanya, shruti, suhani, kavitha, rupali
//   Male                  : shubh, aditya, rahul, rohan, amit, dev, ratan,
//                           varun, manan, sumit, kabir, anand, tarun, gokul

const VOICES = {
  gemini25: "Kore",      // try: "Aoede", "Leda", "Puck", "Charon", "Zephyr"
  gemini31: "Kore",      // try: "Aoede", "Leda", "Puck", "Charon", "Zephyr"
  sarvam:   "priya",     // try: "shubh", "neha", "kavya", "aditya", "rahul"
};

// ── Test cases ────────────────────────────────────────────────────────────────
const TEST_CASES = [
  {
    id: "01_simple_prose",
    label: "Simple Telugu prose",
    text: "ఈ రోజు వాతావరణం చాలా అనుకూలంగా ఉంది. రైతులు పంట పండించడానికి సిద్ధంగా ఉన్నారు.",
    reviewNotes: "Check: natural intonation, sentence breaks, no robotic pauses mid-word.",
  },
  {
    id: "02_code_switching",
    label: "Telugu + English code-switching",
    text: "ప్రభుత్వం Budget లో infrastructure కోసం రూ.50,000 కోట్లు కేటాయించింది. Finance Minister గారు press conference లో ఈ విషయం వెల్లడించారు.",
    reviewNotes: "Check: 'Budget', 'infrastructure', 'Finance Minister', 'press conference' sound natural inside Telugu flow.",
  },
  {
    id: "03_numerals_dates",
    label: "Numbers, dates, percentages",
    text: "జనవరి 15, 2026 నాటికి రాష్ట్రంలో 3,47,892 మంది నిరుద్యోగులు ఉన్నారు. GDP వృద్ధి రేటు 7.4% కి చేరుకుంది.",
    reviewNotes: "Check: '3,47,892' reads in full Telugu, '7.4%' natural, date format correct.",
  },
  {
    id: "04_long_paragraph",
    label: "Long paragraph (596 chars — triggers Sarvam chunking)",
    text: "హైదరాబాద్ లో జరిగిన అంతర్జాతీయ వాణిజ్య సదస్సులో ముఖ్యమ��త్రి పాల్గొన్నారు. ఈ సదస్సులో దేశవిదేశాల నుండి 500 కంపెనీలు పాల్గొన్నాయి. రాష్ట్రానికి రూ.75,000 కోట్ల పెట్టుబడులు వస్తాయని అంచనా వేశారు. సాంకేతిక రంగంలో 50,000 ఉద్యోగాలు కల్పించే అవకాశం ఉందని నిపుణులు అభిప్రాయపడ్డారు. ముఖ్యమంత్రి మాట్లాడుతూ తెలంగాణ రాష్ట్రం పెట్టుబడులకు అత్యంత అనుకూలమైన వాతావరణాన్ని కల్పిస్తుందని అన్నారు. రానున్న రెండు సంవత్సరాలలో మరిన్ని మౌలిక సదుపాయాలు ఏర్పాటు చేయబడతాయని హామీ ఇచ్చారు.",
    reviewNotes: "Listen for audible seam in Sarvam output at ~450-char split point. Gemini handles in one call.",
  },
  {
    id: "05_named_entities",
    label: "Named entities — people, places, parties",
    text: "తెలంగాణ రాష్ట్ర సమితి అధ్యక్షుడు కె. చంద్రశేఖర్ రావు హైదరాబాద్ లో జరిగిన బహిరంగ సభలో మాట్లాడారు. భారతీయ జనతా పార్టీ మరియు కాంగ్రెస్ నాయకులు ఆయన వ్యాఖ్యలను వ్యతిరేకించారు.",
    reviewNotes: "Check: 'కె. చంద్రశేఖర్ రావు' (KCR), 'హైదరాబాద్', 'భారతీయ జనతా పార్టీ', 'కాంగ్రెస్'.",
  },
];

// ── Sarvam provider ───────────────────────────────────────────────────────────
const CHUNK_LIMIT = 450;

function chunkText(text) {
  if (text.length <= CHUNK_LIMIT) return [text];
  const chunks = [];
  const sentences = text.split(/(?<=[।॥|.!?\n])\s*/u).filter((s) => s.trim());
  let current = "";
  for (const sentence of sentences) {
    if (sentence.length > CHUNK_LIMIT) {
      if (current.trim()) { chunks.push(current.trim()); current = ""; }
      const words = sentence.split(/\s+/);
      let part = "";
      for (const word of words) {
        if ((part + " " + word).length > CHUNK_LIMIT) {
          if (part.trim()) chunks.push(part.trim());
          part = word;
        } else {
          part = part ? part + " " + word : word;
        }
      }
      if (part.trim()) current = part.trim();
    } else if ((current + " " + sentence).length > CHUNK_LIMIT) {
      if (current.trim()) chunks.push(current.trim());
      current = sentence;
    } else {
      current = current ? current + " " + sentence : sentence;
    }
  }
  if (current.trim()) chunks.push(current.trim());
  return chunks.filter((c) => c.length > 0);
}

function concatWav(buffers) {
  if (buffers.length === 1) return buffers[0];
  const HEADER = 44;
  const allPcm = buffers.map((b, i) => b.slice(i === 0 ? HEADER : HEADER));
  const pcmTotal = allPcm.reduce((s, p) => s + p.length, 0);
  const result = Buffer.alloc(HEADER + pcmTotal);
  buffers[0].copy(result, 0, 0, HEADER);
  let offset = HEADER;
  for (const pcm of allPcm) { pcm.copy(result, offset); offset += pcm.length; }
  result.writeUInt32LE(result.length - 8, 4);  // RIFF chunk size
  result.writeUInt32LE(pcmTotal, 40);           // data sub-chunk size
  return result;
}

async function synthesizeSarvam(text) {
  const client = new SarvamAIClient({ apiSubscriptionKey: SARVAM_KEY });
  const chunks = chunkText(text);
  const wavBuffers = [];
  const start = performance.now();

  for (const chunk of chunks) {
    const resp = await client.textToSpeech.convert({
      text: chunk,
      target_language_code: "te-IN",
      speaker: "shubh",
      pace: 1.1,
      speech_sample_rate: 48000,
      enable_preprocessing: true,
      model: "bulbul:v3",
      speaker: VOICES.sarvam,
    });
    const audioB64 = resp?.audios?.length ? resp.audios[0] : typeof resp === "string" ? resp : null;
    if (!audioB64) throw new Error(`Sarvam: no audio for chunk "${chunk.slice(0, 40)}…"`);
    wavBuffers.push(Buffer.from(audioB64, "base64"));
  }

  const combined = concatWav(wavBuffers);
  const latencyMs = Math.round(performance.now() - start);
  const durationSec = Math.round(combined.length / (48000 * 2));
  const costUsd = (text.length / 10000) * (15 / 84);

  return { provider: `Sarvam Bulbul:v3 (${VOICES.sarvam})`, audio: combined, ext: "wav", latencyMs, durationSec, chunks: chunks.length, costUsd };
}

// ── Gemini TTS helper ─────────────────────────────────────────────────────────
const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta";

// Gemini returns raw 16-bit PCM (audio/L16 at 24kHz mono) — no WAV header.
// Wrap it in a standard RIFF/WAV container so any player can open it.
function pcmToWav(pcm, sampleRate = 24000, channels = 1, bitsPerSample = 16) {
  const byteRate = sampleRate * channels * (bitsPerSample / 8);
  const blockAlign = channels * (bitsPerSample / 8);
  const dataSize = pcm.length;
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + dataSize, 4);   // file size - 8
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);             // PCM chunk size
  header.writeUInt16LE(1, 20);              // PCM format
  header.writeUInt16LE(channels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE(blockAlign, 32);
  header.writeUInt16LE(bitsPerSample, 34);
  header.write("data", 36);
  header.writeUInt32LE(dataSize, 40);
  return Buffer.concat([header, pcm]);
}

async function callGeminiTTS(model, text, voiceName) {
  const resp = await fetch(`${GEMINI_BASE}/models/${model}:generateContent?key=${GEMINI_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text }] }],
      generationConfig: {
        responseModalities: ["AUDIO"],
        speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName } } },
      },
    }),
  });
  if (!resp.ok) {
    const err = await resp.text();
    throw new Error(`${model} HTTP ${resp.status}: ${err.slice(0, 300)}`);
  }
  const data = await resp.json();
  const part = data?.candidates?.[0]?.content?.parts?.[0];
  if (!part?.inlineData?.data) throw new Error(`${model}: unexpected response shape`);
  return { audioB64: part.inlineData.data, mimeType: part.inlineData.mimeType ?? "audio/L16" };
}

async function synthesizeGemini25(text) {
  const start = performance.now();
  const { audioB64, mimeType } = await callGeminiTTS("gemini-2.5-flash-preview-tts", text, VOICES.gemini25);
  const pcm = Buffer.from(audioB64, "base64");
  // Gemini returns raw PCM (audio/L16 at 24kHz mono) — wrap in WAV header
  const audio = mimeType.toLowerCase().includes("l16") || mimeType.toLowerCase().includes("pcm") ? pcmToWav(pcm) : pcm;
  const latencyMs = Math.round(performance.now() - start);
  const durationSec = Math.round(pcm.length / (24000 * 2));
  const inputTokens = text.length / 4;
  const outputTokens = durationSec * 25;
  const costUsd = (inputTokens / 1e6) * 0.30 + (outputTokens / 1e6) * 2.50;
  return { provider: `Gemini 2.5 Flash TTS (${VOICES.gemini25})`, audio, ext: "wav", latencyMs, durationSec, chunks: 1, costUsd };
}

async function synthesizeGemini31(text, caseId) {
  // Apply audio tags on select cases to test Gemini 3.1's style control
  const taggedText =
    caseId === "04_long_paragraph" ? `[natural pace] ${text}` :
    caseId === "02_code_switching"  ? `[clear] ${text}` :
    text;

  const start = performance.now();
  const { audioB64, mimeType } = await callGeminiTTS("gemini-3.1-flash-tts-preview", taggedText, VOICES.gemini31);
  const pcm = Buffer.from(audioB64, "base64");
  // Gemini returns raw PCM (audio/L16 at 24kHz mono) — wrap in WAV header
  const audio = mimeType.toLowerCase().includes("l16") || mimeType.toLowerCase().includes("pcm") ? pcmToWav(pcm) : pcm;
  const latencyMs = Math.round(performance.now() - start);
  const durationSec = Math.round(pcm.length / (24000 * 2));
  const inputTokens = taggedText.length / 4;
  const outputTokens = durationSec * 25;
  const costUsd = (inputTokens / 1e6) * 1.00 + (outputTokens / 1e6) * 20.00;
  const note = taggedText !== text ? `audio tag: "${taggedText.slice(0, 20)}…"` : undefined;
  return { provider: `Gemini 3.1 Flash TTS (${VOICES.gemini31})`, audio, ext: "wav", latencyMs, durationSec, chunks: 1, costUsd, note };
}

// ── Main ──────────────────────────────────────────────────────────────────────
const outputDir = join(__dirname, "output");
mkdirSync(outputDir, { recursive: true });

const rows = [];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Let any active quota window reset before starting
process.stdout.write("⏳  Waiting 65s for Gemini rate-limit window to reset…");
await sleep(65000);
console.log(" done.\n");

for (const tc of TEST_CASES) {
  console.log(`\n${"─".repeat(68)}`);
  console.log(`▶  ${tc.id}  |  ${tc.label}`);
  console.log(`   ${tc.text.length} chars | ${tc.reviewNotes}`);

  const providers = [
    { slug: "sarvam",   fn: () => synthesizeSarvam(tc.text) },
    { slug: "gemini25", fn: () => synthesizeGemini25(tc.text) },
    { slug: "gemini31", fn: () => synthesizeGemini31(tc.text, tc.id) },
  ];

  for (const p of providers) {
    process.stdout.write(`   ${p.slug.padEnd(12)} → `);
    // Gemini TTS free tier: ~3 RPM per model. 20s gap keeps us safely under.
    if (p.slug.startsWith("gemini")) {
      process.stdout.write("(rate-limit wait 20s) ");
      await sleep(20000);
    }
    try {
      const r = await p.fn();
      const voiceTag = VOICES[p.slug] ?? p.slug;
      const filename = `${tc.id}_${p.slug}_${voiceTag}.${r.ext}`;
      writeFileSync(join(outputDir, filename), r.audio);
      const chunkNote = r.chunks > 1 ? `  [${r.chunks} chunks]` : "";
      const tagNote = r.note ? `  (${r.note})` : "";
      console.log(`${String(r.durationSec).padStart(3)}s  ${String(r.latencyMs).padStart(5)}ms  $${r.costUsd.toFixed(5)}${chunkNote}${tagNote}`);
      rows.push({ ...r, caseId: tc.id, file: filename });
    } catch (err) {
      console.log(`FAILED — ${err.message}`);
    }
  }
}

// ── Summary ───────────────────────────────────────────────────────────────────
console.log(`\n${"═".repeat(90)}`);
console.log("COST SUMMARY");
console.log("═".repeat(90));

for (const provName of ["Sarvam Bulbul:v3", "Gemini 2.5 Flash TTS", "Gemini 3.1 Flash TTS"]) {
  const pRows = rows.filter((r) => r.provider === provName);
  if (!pRows.length) continue;
  const totalCost  = pRows.reduce((s, r) => s + r.costUsd, 0);
  const avgLatency = Math.round(pRows.reduce((s, r) => s + r.latencyMs, 0) / pRows.length);
  const totalDur   = pRows.reduce((s, r) => s + r.durationSec, 0);
  console.log(`  ${provName.padEnd(26)}  avg latency ${String(avgLatency).padStart(5)}ms  total audio ${totalDur}s  total cost $${totalCost.toFixed(5)}`);
}

console.log(`\n✅  ${rows.length} audio files → ${outputDir}`);
console.log("   Play each triplet (sarvam / gemini25 / gemini31) per case.");
console.log("   Key comparisons:");
console.log("     04_long_paragraph — listen for Sarvam chunk seam vs Gemini single-call");
console.log("     02_code_switching — English word naturalness inside Telugu");
console.log("     05_named_entities — KCR, Hyderabad, BJP pronunciation accuracy");
