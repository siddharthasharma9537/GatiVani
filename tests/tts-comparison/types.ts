export interface TTSResult {
  provider: string;
  audioBytes: Uint8Array;
  mimeType: string;
  ext: string;
  latencyMs: number;
  durationSec: number;
  chunks: number;          // always 1 for Gemini; may be >1 for Sarvam on long text
  inputChars: number;
  estimatedCostUsd: number;
  note?: string;           // e.g. which audio tags were injected
}
