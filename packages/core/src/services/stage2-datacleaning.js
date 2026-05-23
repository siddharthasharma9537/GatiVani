/**
 * Stage 2: Data Cleaning & Reformatting
 * - Simple text cleaning (regex-based)
 * - No expensive AI processing
 * - Optimized for speed and cost
 */

export async function processArticleImage(imageBuffer, quality = {}) {
  console.log("[Stage2] Skipping expensive image analysis (using Sarvam OCR instead)");

  return {
    success: true,
    imageBuffer: imageBuffer,
    analysis: { readability: "good" },
    estimatedSize: imageBuffer.length,
  };
}

export async function cleanArticleText(articleText) {
  console.log("[Stage2] Cleaning article text...");

  // Simple regex-based cleaning - no AI needed
  let cleaned = articleText
    // Preserve paragraph structure
    .replace(/\r\n/g, "\n")
    // Remove multiple consecutive newlines (max 2)
    .replace(/\n\n+/g, "\n\n")
    // Remove multiple spaces/tabs but keep single space
    .replace(/[ \t]+/g, " ")
    // Remove trailing spaces on each line
    .replace(/[ \t]+\n/g, "\n")
    // Remove common OCR artifacts
    .replace(/\[Image\s*\d+\]/gi, "")
    .replace(/\[Photo\s*\d+\]/gi, "")
    .replace(/\|\s*[a-z0-9]{2,}\s*\|/gi, "")
    .trim();

  console.log(`[Stage2] Cleaned text: ${articleText.length} → ${cleaned.length} chars`);

  return {
    success: true,
    originalLength: articleText.length,
    cleanedLength: cleaned.length,
    articleText: cleaned,
  };
}

export async function enhanceTextForReadability(text, fontFamily = "default") {
  console.log("[Stage2] Text is ready for audio generation");

  // Skip enhancement - Sarvam OCR already provides clean text
  return {
    success: true,
    originalLength: text.length,
    enhancedLength: text.length,
    articleText: text,
  };
}

export async function stage2ProcessComplete(stage1Result) {
  console.log("[Stage2] Starting data cleaning...");

  try {
    const { rawBuffer, analysis: stage1Analysis, extractedText } = stage1Result;

    // Process image (simplified - no Gemini)
    const imageResult = await processArticleImage(rawBuffer, stage1Analysis.quality);

    // Clean text
    const cleanResult = await cleanArticleText(extractedText || "");

    // Enhance for readability (simplified - no Gemini)
    const enhanceResult = cleanResult.success
      ? await enhanceTextForReadability(cleanResult.articleText)
      : cleanResult;

    return {
      success: imageResult.success && cleanResult.success,
      stage2: {
        image: {
          buffer: imageResult.imageBuffer,
          analysis: imageResult.analysis,
          sizeBytes: imageResult.estimatedSize,
        },
        text: {
          original: extractedText || "",
          cleaned: cleanResult.articleText,
          enhanced: enhanceResult.articleText,
          originalLength: (extractedText || "").length,
          cleanedLength: cleanResult.articleText.length,
          enhancedLength: enhanceResult.articleText.length,
        },
        quality: {
          imageReadability: imageResult.analysis?.readability || "good",
          textCleaned: cleanResult.success,
          textEnhanced: enhanceResult.success,
        },
      },
    };
  } catch (error) {
    console.error("[Stage2] Processing failed:", error.message);
    return {
      success: false,
      error: error.message,
      stage2: {},
    };
  }
}
