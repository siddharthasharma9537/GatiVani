import { generateTeluguAudioDataUrl as azureGenerateAudio } from './azure-tts-service.js';
import { generateSarvamAudioDataUrl as sarvamGenerateAudio, getTeluguVoices } from './sarvam-tts-service.js';

const TTS_PROVIDER = process.env.TTS_PROVIDER || 'azure';
const FALLBACK_ENABLED = process.env.ENABLE_TTS_FALLBACK === 'true';

export async function generateAudioWithFallback(text, language = 'te', speaker = null) {
  const providers = getTTSProviderOrder();

  for (const provider of providers) {
    try {
      console.log(`[TTS] Attempting ${provider}${speaker ? ` (${speaker})` : ''}...`);
      let audioUrl;

      if (provider === 'azure') {
        audioUrl = await azureGenerateAudio(text, language);
      } else if (provider === 'sarvam') {
        audioUrl = await sarvamGenerateAudio(text, language, speaker);
      }

      if (audioUrl) {
        console.log(`[TTS] ✓ ${provider} succeeded`);
        return {
          success: true,
          audioUrl,
          provider,
          text,
          language,
          speaker: speaker || 'default',
        };
      }
    } catch (error) {
      console.warn(`[TTS] ${provider} failed:`, error.message);

      if (provider === providers[providers.length - 1]) {
        return {
          success: false,
          audioUrl: null,
          provider,
          error: error.message,
          text,
          language,
        };
      }
    }
  }

  return {
    success: false,
    audioUrl: null,
    error: 'All TTS providers failed',
    text,
    language,
  };
}

function getTTSProviderOrder() {
  switch (TTS_PROVIDER.toLowerCase()) {
    case 'sarvam':
      return FALLBACK_ENABLED ? ['sarvam', 'azure'] : ['sarvam'];
    case 'fallback':
      return ['azure', 'sarvam'];
    case 'azure':
    default:
      return FALLBACK_ENABLED ? ['azure', 'sarvam'] : ['azure'];
  }
}

export function getCurrentTTSProvider() {
  const order = getTTSProviderOrder();
  return {
    primary: order[0],
    fallback: order.length > 1 ? order[1] : null,
    fallbackEnabled: FALLBACK_ENABLED,
  };
}

export function getTeluguTTSVoices() {
  return getTeluguVoices();
}
