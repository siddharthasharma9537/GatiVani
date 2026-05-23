import { SarvamAIClient } from "sarvamai";

const SARVAM_API_KEY = process.env.SARVAM_API_KEY;

// Telugu voices available in Sarvam bulbul:v3 model
const TELUGU_VOICES = {
  shubh: { name: "Shubh", gender: "male", description: "Natural male voice" },
  shreya: { name: "Shreya", gender: "female", description: "Natural female voice" },
  anushka: { name: "Anushka", gender: "female", description: "Professional female voice" },
  vidya: { name: "Vidya", gender: "female", description: "Warm female voice" },
  manisha: { name: "Manisha", gender: "female", description: "Clear female voice" },
  arya: { name: "Arya", gender: "male", description: "Calm male voice" },
};

const VOICE_MAP = {
  te: "shubh", // Default Telugu voice (CORRECT for Telugu!)
  hi: "tanya",
  en: "amit",
};

const LANGUAGE_CONFIG = {
  te: {
    language_code: "te-IN",
    sample_rate: 48000, // CORRECT for Telugu
    voices: TELUGU_VOICES,
    defaultVoice: "shubh",
  },
  hi: {
    language_code: "hi-IN",
    sample_rate: 22050,
    voices: { tanya: { name: "Tanya", gender: "female" } },
    defaultVoice: "tanya",
  },
  en: {
    language_code: "en-IN",
    sample_rate: 22050,
    voices: { amit: { name: "Amit", gender: "male" } },
    defaultVoice: "amit",
  },
};

export async function generateSarvamAudio(text, language = "te", speaker = null) {
  if (!SARVAM_API_KEY) {
    throw new Error("SARVAM_API_KEY not configured");
  }

  try {
    const client = new SarvamAIClient({
      apiSubscriptionKey: SARVAM_API_KEY,
    });

    const config = LANGUAGE_CONFIG[language] || LANGUAGE_CONFIG.te;
    const selectedSpeaker = speaker || config.defaultVoice;

    console.log(`[Sarvam TTS] Converting to ${language} (${selectedSpeaker}, ${config.sample_rate}Hz)...`);

    const response = await client.textToSpeech.convert({
      text: text,
      target_language_code: config.language_code,
      speaker: selectedSpeaker,
      pace: 1.1,
      speech_sample_rate: config.sample_rate,
      enable_preprocessing: true,
      model: "bulbul:v3",
    });

    if (!response) {
      throw new Error("No audio data returned from Sarvam TTS");
    }

    console.log("[Sarvam TTS] ✓ Audio generated successfully");

    // Extract audio from Sarvam API response
    // Response format: { request_id, audios: [base64AudioString, ...] }
    let audioData = null;

    if (response.audios && Array.isArray(response.audios) && response.audios.length > 0) {
      // Get first audio from the audios array
      audioData = response.audios[0];
    } else if (typeof response === 'string') {
      // If response is already a string, use it directly
      audioData = response;
    } else if (Buffer.isBuffer(response)) {
      // If response is a buffer, convert to base64
      return response.toString('base64');
    } else {
      throw new Error("Unexpected Sarvam TTS response format");
    }

    // If audioData is a Buffer, convert to base64
    if (Buffer.isBuffer(audioData)) {
      return audioData.toString('base64');
    }

    // If it's a string, assume it's already base64
    if (typeof audioData === 'string') {
      return audioData;
    }

    throw new Error("Could not extract audio data from Sarvam response");
  } catch (error) {
    console.error("[Sarvam TTS Error]", {
      message: error.message,
      code: error.code,
    });
    throw error;
  }
}

export async function generateSarvamAudioDataUrl(text, language = "te", speaker = null) {
  const audioBase64 = await generateSarvamAudio(text, language, speaker);
  return `data:audio/mpeg;base64,${audioBase64}`;
}

// Get all available voices for a language
export function getAvailableVoices(language = "te") {
  const config = LANGUAGE_CONFIG[language] || LANGUAGE_CONFIG.te;
  return config.voices;
}

// Get Telugu voices specifically (for Android mobile UI)
export function getTeluguVoices() {
  return {
    voices: TELUGU_VOICES,
    defaultVoice: "shubh",
    language: "te-IN",
    sampleRate: 48000,
    model: "bulbul:v3",
  };
}

// Get all supported languages and their voices
export function getAllSupportedLanguages() {
  return {
    te: {
      name: "Telugu",
      nativeName: "తెలుగు",
      voices: TELUGU_VOICES,
      defaultVoice: "shubh",
      languageCode: "te-IN",
      sampleRate: 48000,
    },
    hi: {
      name: "Hindi",
      nativeName: "हिंदी",
      voices: { tanya: { name: "Tanya", gender: "female" } },
      defaultVoice: "tanya",
      languageCode: "hi-IN",
      sampleRate: 22050,
    },
    en: {
      name: "English",
      nativeName: "English",
      voices: { amit: { name: "Amit", gender: "male" } },
      defaultVoice: "amit",
      languageCode: "en-IN",
      sampleRate: 22050,
    },
  };
}
