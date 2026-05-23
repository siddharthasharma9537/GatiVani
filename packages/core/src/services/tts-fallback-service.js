import { generateTeluguAudioDataUrl as azureGenerateAudio } from './azure-tts-service.js';
import { generateSarvamAudioDataUrl as sarvamGenerateAudio } from './sarvam-tts-service.js';

const TTS_PROVIDER = process.env.TTS_PROVIDER || 'azure'; // 'azure', 'sarvam', or 'fallback'
const FALLBACK_ENABLED = process.env.ENABLE_TTS_FALLBACK === 'true';

export async function generateAudioWithFallback(text, language = 'te') {
  const providers = getTTSProviderOrder();

  for (const provider of providers) {
    try {
      console.log(`[TTS] Attempting ${provider}...`);
      let audioUrl;

      if (provider === 'azure') {
        audioUrl = await azureGenerateAudio(text, language);
      } else if (provider === 'sarvam') {
        audioUrl = await sarvamGenerateAudio(text, language);
      }

      if (audioUrl) {
        console.log(`[TTS] ✓ ${provider} succeeded`);
        return {
          success: true,
          audioUrl,
          provider,
          text,
          language,
        };
      }
    } catch (error) {
      console.warn(`[TTS] ${provider} failed:`, error.message);

      if (provider === providers[providers.length - 1]) {
        // Last provider failed
        return {
          success: false,
          audioUrl: null,
          provider,
          error: error.message,
          text,
          language,
        };
      }
      // Try next provider
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

export async function testTTSServices() {
  const testText = 'Test audio generation';
  const results = {
    azure: null,
    sarvam: null,
  };

  // Test Azure
  try {
    await azureGenerateAudio(testText, 'te');
    results.azure = { status: 'working', timestamp: new Date() };
    console.log('[TTS Test] Azure: ✓');
  } catch (error) {
    results.azure = { status: 'failed', error: error.message, timestamp: new Date() };
    console.log('[TTS Test] Azure: ✗', error.message);
  }

  // Test Sarvam
  try {
    await sarvamGenerateAudio(testText, 'te');
    results.sarvam = { status: 'working', timestamp: new Date() };
    console.log('[TTS Test] Sarvam: ✓');
  } catch (error) {
    results.sarvam = { status: 'failed', error: error.message, timestamp: new Date() };
    console.log('[TTS Test] Sarvam: ✗', error.message);
  }

  return {
    currentProvider: getCurrentTTSProvider(),
    serviceStatus: results,
    timestamp: new Date(),
  };
}
