import axios from 'axios';
import FormData from 'form-data';

const SARVAM_STT_URL = 'https://api.sarvam.ai/speech-to-text';
const SARVAM_API_KEY = process.env.SARVAM_API_KEY;

const LANGUAGE_CODES = {
  te: 'te-IN', // Telugu India
  hi: 'hi-IN', // Hindi India
  en: 'en-IN', // English India
  ta: 'ta-IN', // Tamil India
  ml: 'ml-IN', // Malayalam India
};

export async function transcribeSpeech(audioBuffer, language = 'te', mimeType = 'audio/mpeg') {
  if (!SARVAM_API_KEY) {
    throw new Error('SARVAM_API_KEY not configured');
  }

  try {
    const form = new FormData();
    form.append('file', audioBuffer, { filename: 'audio.mp3', contentType: mimeType });
    form.append('language_code', LANGUAGE_CODES[language] || LANGUAGE_CODES.te);
    form.append('enable_preprocessing', 'true');

    const response = await axios.post(SARVAM_STT_URL, form, {
      headers: {
        ...form.getHeaders(),
        'API-Subscription-Key': SARVAM_API_KEY,
      },
    });

    if (!response.data?.transcript) {
      throw new Error('No transcript in Sarvam response');
    }

    return {
      success: true,
      transcript: response.data.transcript,
      language: language,
      confidence: response.data.confidence || 0.85,
      processingTime: response.data.processing_time_ms || 0,
    };
  } catch (error) {
    console.error('[Sarvam STT Error]', {
      status: error.response?.status,
      message: error.message,
      data: error.response?.data,
    });

    return {
      success: false,
      transcript: '',
      language: language,
      error: error.message,
    };
  }
}

export async function transcribeWithPunctuation(audioBuffer, language = 'te') {
  try {
    const result = await transcribeSpeech(audioBuffer, language);

    if (result.success) {
      const punctuatedText = addPunctuation(result.transcript);
      return {
        ...result,
        transcript: punctuatedText,
      };
    }

    return result;
  } catch (error) {
    return {
      success: false,
      transcript: '',
      language: language,
      error: error.message,
    };
  }
}

function addPunctuation(text) {
  if (!text) return '';

  // Simple punctuation addition
  let result = text.trim();

  // Add periods at sentence boundaries (heuristic)
  result = result.replace(/([।।॥])/g, '.'); // Sanskrit punctuation to period
  result = result.replace(/([a-z]{2,})\s+([A-Z])/g, '$1. $2'); // Add period before capitals

  // Add final period if missing
  if (!result.endsWith('.') && !result.endsWith('?') && !result.endsWith('!')) {
    result += '.';
  }

  return result;
}

export function getSupportedLanguages() {
  return {
    te: { name: 'Telugu', code: 'te-IN' },
    hi: { name: 'Hindi', code: 'hi-IN' },
    en: { name: 'English', code: 'en-IN' },
    ta: { name: 'Tamil', code: 'ta-IN' },
    ml: { name: 'Malayalam', code: 'ml-IN' },
  };
}

export async function getAudioDuration(audioBuffer) {
  // This is a placeholder - actual implementation would parse MP3 metadata
  try {
    const durationEstimate = audioBuffer.length / (128000 / 8); // Rough estimate for 128kbps audio
    return Math.round(durationEstimate);
  } catch (error) {
    return 0;
  }
}
