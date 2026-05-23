import axios from 'axios';

const SARVAM_API_URL = 'https://api.sarvam.ai/text-to-speech';
const SARVAM_API_KEY = process.env.SARVAM_API_KEY;

const VOICE_MAP = {
  te: 'meera', // Telugu
  hi: 'harshita', // Hindi
  en: 'john', // English
};

export async function generateSarvamAudio(text, language = 'te') {
  if (!SARVAM_API_KEY) {
    throw new Error('SARVAM_API_KEY not configured');
  }

  try {
    const voice = VOICE_MAP[language] || VOICE_MAP.te;

    const response = await axios.post(
      SARVAM_API_URL,
      {
        inputs: [text],
        target_language_code: language,
        speaker: voice,
        pitch: 1.0,
        pace: 1.0,
        loudness: 1.0,
      },
      {
        headers: {
          'Content-Type': 'application/json',
          'API-Subscription-Key': SARVAM_API_KEY,
        },
      }
    );

    if (response.data?.audios && response.data.audios.length > 0) {
      return response.data.audios[0];
    }

    throw new Error('No audio data in Sarvam response');
  } catch (error) {
    console.error('[Sarvam TTS Error]', {
      status: error.response?.status,
      message: error.message,
      data: error.response?.data,
    });
    throw error;
  }
}

export async function generateSarvamAudioDataUrl(text, language = 'te') {
  const audioBase64 = await generateSarvamAudio(text, language);
  return `data:audio/mpeg;base64,${audioBase64}`;
}

export function isTeluguLanguage(language) {
  return language?.toLowerCase() === 'te' || language?.toLowerCase() === 'telugu';
}

export function getAvailableVoices() {
  return {
    te: { name: 'Meera', language: 'Telugu' },
    hi: { name: 'Harshita', language: 'Hindi' },
    en: { name: 'John', language: 'English' },
  };
}
