import { env } from "../config/env.js";

const { GoogleGenerativeAI } = await import("@google/generative-ai");
const genAI = new GoogleGenerativeAI(env.geminiApiKey);

/**
 * Stage 1: Pre-Processing
 * - Analyze document layout
 * - Identify article boundaries
 * - Remove ads
 * - Separate article image from body text
 */

export async function preprocessDocument(fileBuffer, mimeType, filename) {
  console.log("[Stage1] Analyzing document layout and separating content...");

  const model = genAI.getGenerativeModel({ model: env.geminiModel });

  // Convert buffer to base64 for Gemini Vision
  const base64Data = fileBuffer.toString("base64");

  // Analyze layout with Gemini Vision
  const analysisPrompt = `You are an expert newspaper analyzer. Analyze this document image/PDF and provide:

1. **Article Boundaries**: Describe where the main article starts and ends
2. **Ad Detection**: Identify any advertisement spaces and their locations
3. **Cover Image**: Describe if there's an article cover image and its location
4. **Article Body**: Describe the main text area
5. **Metadata**: Extract publication name, date if visible, author if visible

Respond in JSON format:
{
  "hasCoverImage": boolean,
  "coverImageLocation": "top|middle|side|none",
  "adSpaces": [{ "location": "string", "type": "string" }],
  "articleBoundaries": { "startLine": number, "endLine": number },
  "hasMainText": boolean,
  "estimatedPages": number,
  "metadata": {
    "publication": "string or null",
    "date": "string or null",
    "author": "string or null"
  },
  "quality": {
    "readability": "good|fair|poor",
    "imageQuality": "high|medium|low",
    "textClarity": "clear|moderate|blurry"
  }
}`;

  try {
    const response = await model.generateContent([
      {
        inlineData: {
          data: base64Data,
          mimeType: mimeType,
        },
      },
      { text: analysisPrompt },
    ]);

    let analysisText = response.response.text();
    // Extract JSON from response
    const jsonMatch = analysisText.match(/\{[\s\S]*\}/);
    const analysis = JSON.parse(jsonMatch[0]);

    console.log("[Stage1] Layout analysis complete:", analysis);

    return {
      success: true,
      analysis,
      rawBuffer: fileBuffer,
      mimeType,
      filename,
    };
  } catch (error) {
    console.error("[Stage1] Layout analysis failed:", error.message);
    // Fallback: treat entire document as article
    return {
      success: false,
      error: error.message,
      analysis: {
        hasCoverImage: false,
        hasMainText: true,
        quality: { readability: "unknown" },
      },
      rawBuffer: fileBuffer,
      mimeType,
      filename,
    };
  }
}

/**
 * Extract article content (text + metadata) from analyzed document
 */
export async function extractArticleContent(stage1Result) {
  console.log("[Stage1] Extracting article content...");

  const model = genAI.getGenerativeModel({ model: env.geminiModel });
  const { rawBuffer, mimeType, analysis } = stage1Result;

  const base64Data = rawBuffer.toString("base64");

  const extractionPrompt = `Extract the COMPLETE main article text from this document.

IMPORTANT RULES:
1. Extract ONLY the main article body text
2. PRESERVE original language exactly (don't translate or rewrite)
3. Keep all original punctuation and formatting
4. Maintain paragraph structure
5. Remove any advertisements, headers, footers, page numbers
6. Return the complete article without any modifications

Just provide the raw article text, nothing else.`;

  try {
    const response = await model.generateContent([
      {
        inlineData: {
          data: base64Data,
          mimeType: mimeType,
        },
      },
      { text: extractionPrompt },
    ]);

    const articleText = response.response.text();

    console.log(
      `[Stage1] Extracted ${articleText.length} characters from article`
    );

    return {
      success: true,
      articleText,
      metadata: analysis.metadata,
      quality: analysis.quality,
    };
  } catch (error) {
    console.error("[Stage1] Content extraction failed:", error.message);
    return {
      success: false,
      error: error.message,
      articleText: "",
    };
  }
}
