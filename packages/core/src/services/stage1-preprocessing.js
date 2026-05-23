import { performOCR } from "./sarvam-vision-service.js";

/**
 * Stage 1: Pre-Processing
 * - Extract text using Sarvam OCR (optimized for Indian languages)
 * - Fast and cost-effective alternative to Gemini Vision
 */

export async function preprocessDocument(fileBuffer, mimeType, filename) {
  console.log("[Stage1] Extracting text using Sarvam OCR...");

  try {
    // Use Sarvam OCR for text extraction
    const ocrResult = await performOCR(fileBuffer, "te");

    if (!ocrResult.success) {
      console.warn("[Stage1] OCR failed, returning fallback");
      return {
        success: false,
        error: ocrResult.error,
        analysis: {
          hasCoverImage: false,
          hasMainText: false,
          quality: { readability: "unknown" },
        },
        rawBuffer: fileBuffer,
        mimeType,
        filename,
        extractedText: "",
      };
    }

    console.log(
      `[Stage1] Successfully extracted ${ocrResult.text.length} characters`
    );

    return {
      success: true,
      analysis: {
        hasCoverImage: false,
        hasMainText: ocrResult.text.length > 100,
        quality: {
          readability: ocrResult.confidence > 0.8 ? "good" : "fair",
          textClarity: ocrResult.confidence > 0.8 ? "clear" : "moderate",
        },
      },
      rawBuffer: fileBuffer,
      mimeType,
      filename,
      extractedText: ocrResult.text,
    };
  } catch (error) {
    console.error("[Stage1] Preprocessing failed:", error.message);
    return {
      success: false,
      error: error.message,
      analysis: {
        hasCoverImage: false,
        hasMainText: false,
        quality: { readability: "unknown" },
      },
      rawBuffer: fileBuffer,
      mimeType,
      filename,
      extractedText: "",
    };
  }
}

/**
 * Extract article content from Stage 1 preprocessing
 */
export async function extractArticleContent(stage1Result) {
  console.log("[Stage1] Preparing article content...");

  const { extractedText, success } = stage1Result;

  if (!success || !extractedText) {
    return {
      success: false,
      error: "No text extracted",
      articleText: "",
    };
  }

  return {
    success: true,
    articleText: extractedText,
    metadata: {
      publication: null,
      date: null,
      author: null,
    },
    quality: stage1Result.analysis.quality,
  };
}
