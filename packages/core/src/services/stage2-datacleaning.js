import { env } from "../config/env.js";

const { GoogleGenerativeAI } = await import("@google/generative-ai");
const genAI = new GoogleGenerativeAI(env.geminiApiKey);

/**
 * Stage 2: Data Cleaning & Reformatting
 * - Image optimization and quality assessment
 * - Text cleaning and error correction
 * - AI-assisted text rewriting for readability
 */

export async function processArticleImage(imageBuffer, quality = {}) {
  console.log("[Stage2] Processing article image...");

  const model = genAI.getGenerativeModel({ model: env.geminiModel });
  const base64Data = imageBuffer.toString("base64");

  // Analyze image quality with Gemini Vision
  const qualityPrompt = `Analyze this image and provide:
1. **Blur Assessment**: Is this image blurry? Rate clarity (clear|moderate|blurry)
2. **Readability**: Can text be read clearly? (good|fair|poor)
3. **Size Optimization**: Estimate optimal format (jpeg|webp) and compression level (1-10)
4. **Resolution**: Approximate minimum width needed for mobile display
5. **Recommendations**: Specific improvements needed (contrast, brightness, rotation, etc.)

Respond in JSON:
{
  "isBlurry": boolean,
  "clarity": "clear|moderate|blurry",
  "readability": "good|fair|poor",
  "recommendedFormat": "jpeg|webp",
  "compressionLevel": number,
  "minWidth": number,
  "recommendations": ["string"],
  "isOptimizable": boolean
}`;

  try {
    const response = await model.generateContent([
      {
        inlineData: {
          data: base64Data,
          mimeType: "image/jpeg",
        },
      },
      { text: qualityPrompt },
    ]);

    let analysisText = response.response.text();
    const jsonMatch = analysisText.match(/\{[\s\S]*\}/);
    const imageAnalysis = JSON.parse(jsonMatch[0]);

    console.log("[Stage2] Image quality analysis:", imageAnalysis);

    // For now, return analyzed quality without local processing
    // In production, would use Sharp library for actual resizing
    return {
      success: true,
      imageBuffer: imageBuffer, // Keep original for now
      analysis: imageAnalysis,
      estimatedSize: imageBuffer.length,
    };
  } catch (error) {
    console.error("[Stage2] Image processing failed:", error.message);
    return {
      success: false,
      error: error.message,
      imageBuffer: imageBuffer,
      analysis: { readability: "unknown" },
    };
  }
}

export async function cleanArticleText(articleText) {
  console.log("[Stage2] Cleaning article text...");

  // First pass: simple regex-based cleaning
  let cleaned = articleText
    // Preserve paragraph structure
    .replace(/\r\n/g, "\n")
    // Remove multiple consecutive newlines (max 2)
    .replace(/\n\n+/g, "\n\n")
    // Remove multiple spaces/tabs but keep single space
    .replace(/[ \t]+/g, " ")
    // Remove trailing spaces on each line
    .replace(/[ \t]+\n/g, "\n")
    // Remove common OCR artifacts and markers
    .replace(/\[Image\s*\d+\]/gi, "")
    .replace(/\[Photo\s*\d+\]/gi, "")
    .replace(/\|\s*[a-z0-9]{2,}\s*\|/gi, "") // Remove metadata pipes
    .trim();

  // Second pass: Gemini-assisted correction for OCR errors
  const model = genAI.getGenerativeModel({ model: env.geminiModel });

  const cleaningPrompt = `Fix OCR errors in this Telugu/Hindi newspaper text while PRESERVING:
1. Original language exactly (no translation)
2. Paragraph structure and line breaks
3. All original meaning and context
4. Names, places, numbers exactly as they appear

Only fix:
- Obvious character substitutions (l→I, 0→O, etc.)
- Double spaces or weird whitespace
- Clear OCR glitches

Return ONLY the corrected text, no explanations or modifications beyond OCR fixes.

TEXT TO CLEAN:
${cleaned.slice(0, 4000)}`;

  try {
    const response = await model.generateContent(cleaningPrompt);
    const correctedText = response.response.text().trim();

    console.log(`[Stage2] Cleaned text: ${cleaned.length} → ${correctedText.length} chars`);

    return {
      success: true,
      originalLength: articleText.length,
      cleanedLength: correctedText.length,
      articleText: correctedText,
    };
  } catch (error) {
    console.error("[Stage2] Text cleaning failed:", error.message);
    // Return original if Gemini fails
    return {
      success: false,
      error: error.message,
      articleText: cleaned,
    };
  }
}

export async function enhanceTextForReadability(text, fontFamily = "default") {
  console.log(`[Stage2] Enhancing text for readability (font: ${fontFamily})...`);

  const model = genAI.getGenerativeModel({ model: env.geminiModel });

  const enhancementPrompt = `Improve readability of this Telugu/Hindi newspaper text while STRICTLY PRESERVING:
1. Original language (no translation or rewriting)
2. All original content and meaning
3. Paragraph structure
4. Punctuation and capitalization
5. Names, numbers, dates exactly as they appear

Only enhance:
- Add proper spacing around punctuation if needed (e.g., " , " → ", ")
- Ensure consistent quote marks ("..." instead of mixed)
- Fix obvious formatting (extra spaces, broken words)
- Add line breaks between logical sections if text is one huge paragraph
- Ensure bullets/lists format cleanly

Font: ${fontFamily} (adjust for rendering if needed)

Return the enhanced text maintaining 100% fidelity to original content.

TEXT:
${text.slice(0, 4000)}`;

  try {
    const response = await model.generateContent(enhancementPrompt);
    const enhancedText = response.response.text().trim();

    console.log(`[Stage2] Enhanced text readability: ${text.length} → ${enhancedText.length} chars`);

    return {
      success: true,
      originalLength: text.length,
      enhancedLength: enhancedText.length,
      articleText: enhancedText,
    };
  } catch (error) {
    console.error("[Stage2] Text enhancement failed:", error.message);
    return {
      success: false,
      error: error.message,
      articleText: text,
    };
  }
}

export async function stage2ProcessComplete(stage1Result) {
  console.log("[Stage2] Starting complete data cleaning process...");

  try {
    const { rawBuffer, mimeType, analysis: stage1Analysis } = stage1Result;

    // Process image
    const imageResult = await processArticleImage(rawBuffer, stage1Analysis.quality);

    // Get article text (already extracted in Stage 1)
    const articleContentResult = await stage1Result.articleContent ||
      (async () => ({
        success: false,
        articleText: "",
      }))();

    const articleText = articleContentResult.articleText || "";

    // Clean text
    const cleanResult = await cleanArticleText(articleText);

    // Enhance for readability
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
          original: articleText,
          cleaned: cleanResult.articleText,
          enhanced: enhanceResult.articleText,
          originalLength: articleText.length,
          cleanedLength: cleanResult.articleText.length,
          enhancedLength: enhanceResult.articleText.length,
        },
        quality: {
          imageReadability: imageResult.analysis?.readability || "unknown",
          textCleaned: cleanResult.success,
          textEnhanced: enhanceResult.success,
        },
      },
    };
  } catch (error) {
    console.error("[Stage2] Complete processing failed:", error.message);
    return {
      success: false,
      error: error.message,
      stage2: {},
    };
  }
}
