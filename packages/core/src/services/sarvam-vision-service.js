import axios from 'axios';
import * as fs from 'fs';

const SARVAM_VISION_URL = 'https://api.sarvam.ai/document-intelligence';
const SARVAM_API_KEY = process.env.SARVAM_API_KEY;

export async function analyzeDocumentWithSarvam(imageBuffer, mimeType = 'image/jpeg') {
  if (!SARVAM_API_KEY) {
    throw new Error('SARVAM_API_KEY not configured');
  }

  try {
    const base64Image = imageBuffer.toString('base64');

    const response = await axios.post(
      SARVAM_VISION_URL,
      {
        image: `data:${mimeType};base64,${base64Image}`,
        query: 'Extract all text from this document. Preserve layout and structure.',
      },
      {
        headers: {
          'Content-Type': 'application/json',
          'API-Subscription-Key': SARVAM_API_KEY,
        },
      }
    );

    if (!response.data) {
      throw new Error('No response from Sarvam Vision API');
    }

    return {
      success: true,
      text: response.data.text || '',
      confidence: response.data.confidence || 0.85,
      language: response.data.language || 'te',
      metadata: {
        hasImages: response.data.image_count || 0,
        pageCount: response.data.page_count || 1,
        processingTime: response.data.processing_time_ms || 0,
      },
    };
  } catch (error) {
    console.error('[Sarvam Vision Error]', {
      status: error.response?.status,
      message: error.message,
      data: error.response?.data,
    });

    return {
      success: false,
      error: error.message,
      text: '',
      confidence: 0,
    };
  }
}

export async function extractTextFromImage(imageBuffer) {
  return analyzeDocumentWithSarvam(imageBuffer);
}

export async function detectLanguage(text) {
  if (!text || text.length < 5) {
    return 'te'; // Default to Telugu
  }

  try {
    const response = await axios.post(
      'https://api.sarvam.ai/language-detection',
      { text },
      {
        headers: {
          'API-Subscription-Key': SARVAM_API_KEY,
          'Content-Type': 'application/json',
        },
      }
    );

    const language = response.data?.language || 'te';
    const confidence = response.data?.confidence || 0;

    return { language, confidence };
  } catch (error) {
    console.warn('[Language Detection Error]', error.message);
    return { language: 'te', confidence: 0 };
  }
}

export async function performOCR(imageBuffer, language = 'te') {
  try {
    const result = await analyzeDocumentWithSarvam(imageBuffer);

    if (result.success) {
      return {
        success: true,
        text: result.text,
        language: language,
        confidence: result.confidence,
      };
    }

    return {
      success: false,
      text: '',
      language: language,
      error: result.error,
    };
  } catch (error) {
    return {
      success: false,
      text: '',
      language: language,
      error: error.message,
    };
  }
}
