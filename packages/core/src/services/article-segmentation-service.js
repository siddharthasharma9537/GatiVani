import { env } from "../config/env.js";

const { GoogleGenerativeAI } = await import("@google/generative-ai");
const genAI = new GoogleGenerativeAI(env.geminiApiKey);

const SECTION_PATTERNS = {
  Politics: /politics|political|government|parliament|election|minister|chief minister|राजनीति|రాజకీయ/i,
  Business: /business|market|economy|finance|trade|company|corporate|व्यापार|వ్యాపారం/i,
  Sports: /sports|cricket|football|match|player|game|team|खेल|ఖేలు/i,
  Entertainment: /entertainment|movie|film|actor|music|celebrity|बॉलीवुड|సినిమా/i,
  Health: /health|medical|disease|doctor|hospital|treatment|स्वास्थ्य|ఆరోగ్య/i,
  Education: /education|school|college|student|university|exam|शिक्षा|విద్య/i,
};

const DEFAULT_SECTION = "General";

export async function segmentArticles(documentBuffer, metadata = {}) {
  console.log("[ArticleSegmentation] Analyzing document for article boundaries...");

  const model = genAI.getGenerativeModel({ model: env.geminiModel });
  const base64Data = documentBuffer.toString("base64");

  const segmentationPrompt = `You are an expert newspaper layout analyzer. Analyze this newspaper document image/PDF and identify ALL articles on the page(s).

For each article found, provide:
1. Title (if visible, otherwise inferred from headline)
2. Section/Category (Politics, Business, Sports, Entertainment, Health, Education, or other)
3. Approximate content preview (first 100 chars)
4. Page number where article appears
5. Position on page as bounding box: {x: percentage from left (0-100), y: percentage from top (0-100), width: percentage, height: percentage}
6. Confidence score (0-100) for detection

Return as JSON array with structure:
{
  "articlesFound": number,
  "articles": [
    {
      "id": "article_1",
      "title": "string",
      "section": "string",
      "contentPreview": "string",
      "page": number,
      "position": {
        "x": number,
        "y": number,
        "width": number,
        "height": number
      },
      "confidence": number,
      "hasImage": boolean,
      "estimatedLength": "short|medium|long"
    }
  ],
  "totalPages": number,
  "analysisQuality": "high|medium|low"
}

IMPORTANT RULES:
- Identify article boundaries clearly (section headers, bylines, spacing)
- List articles in reading order (top-to-bottom, left-to-right)
- Include small articles and ads separately if they have distinct titles
- Use percentages (0-100) for position coordinates, not pixels
- Be conservative with confidence scores (only 90+ if very certain)`;

  try {
    const response = await model.generateContent([
      {
        inlineData: {
          data: base64Data,
          mimeType: metadata.mimeType || "image/jpeg",
        },
      },
      { text: segmentationPrompt },
    ]);

    let responseText = response.response.text();
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    const segmentation = JSON.parse(jsonMatch[0]);

    console.log(
      `[ArticleSegmentation] Found ${segmentation.articlesFound} articles`
    );

    const enrichedArticles = segmentation.articles.map((article) => ({
      ...article,
      detectedSection: classifyArticleSectionSync(article.title + " " + article.contentPreview),
    }));

    return {
      success: true,
      segmentation: {
        ...segmentation,
        articles: enrichedArticles,
      },
      metadata,
    };
  } catch (error) {
    console.error("[ArticleSegmentation] Segmentation failed:", error.message);

    return {
      success: false,
      error: error.message,
      segmentation: {
        articlesFound: 1,
        articles: [
          {
            id: "article_1",
            title: metadata.filename || "Document",
            section: "General",
            contentPreview: "Unable to segment - treating as single article",
            page: 1,
            position: { x: 0, y: 0, width: 100, height: 100 },
            confidence: 0,
            hasImage: false,
            estimatedLength: "long",
            detectedSection: "General",
          },
        ],
        totalPages: 1,
        analysisQuality: "low",
      },
      metadata,
    };
  }
}

export async function extractArticleImage(
  documentBuffer,
  position,
  page,
  mimeType = "image/jpeg"
) {
  console.log(
    `[ArticleSegmentation] Extracting article image from page ${page}, position: ${JSON.stringify(position)}`
  );

  try {
    if (!position || !position.x || position.width === undefined) {
      console.warn("[ArticleSegmentation] Invalid position coordinates");
      return {
        success: false,
        error: "Invalid position coordinates",
        imageBuffer: documentBuffer,
      };
    }

    // For Vision API documents (PDF, multi-page), we'd need additional processing
    // For now, return the document buffer as-is with crop hints
    // Production: use image processing library (Sharp) to actually crop based on coordinates
    return {
      success: true,
      imageBuffer: documentBuffer,
      position,
      page,
      cropHints: {
        x: Math.round((position.x / 100) * 1024),
        y: Math.round((position.y / 100) * 1024),
        width: Math.round((position.width / 100) * 1024),
        height: Math.round((position.height / 100) * 1024),
      },
      note: "Crop hints provided; actual cropping requires image processing library",
    };
  } catch (error) {
    console.error("[ArticleSegmentation] Image extraction failed:", error.message);
    return {
      success: false,
      error: error.message,
      imageBuffer: documentBuffer,
    };
  }
}

export function classifyArticleSectionSync(content) {
  for (const [section, pattern] of Object.entries(SECTION_PATTERNS)) {
    if (pattern.test(content)) {
      return section;
    }
  }
  return DEFAULT_SECTION;
}

export async function classifyArticleSection(content) {
  console.log("[ArticleSegmentation] Classifying article section...");

  const syncSection = classifyArticleSectionSync(content);
  if (syncSection !== DEFAULT_SECTION) {
    return {
      success: true,
      section: syncSection,
      method: "pattern_matching",
      confidence: 85,
    };
  }

  const model = genAI.getGenerativeModel({ model: env.geminiModel });

  const classificationPrompt = `Classify this newspaper article content into ONE category:
- Politics
- Business
- Sports
- Entertainment
- Health
- Education
- General (if none above fit)

Content: ${content.slice(0, 500)}

Respond with JSON:
{
  "section": "string (one of the categories above)",
  "confidence": number (0-100),
  "reasoning": "string"
}`;

  try {
    const response = await model.generateContent(classificationPrompt);
    let responseText = response.response.text();
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    const classification = JSON.parse(jsonMatch[0]);

    console.log(
      `[ArticleSegmentation] Classified as: ${classification.section} (${classification.confidence}%)`
    );

    return {
      success: true,
      section: classification.section,
      method: "gemini_vision",
      confidence: classification.confidence,
      reasoning: classification.reasoning,
    };
  } catch (error) {
    console.error("[ArticleSegmentation] Classification failed:", error.message);
    return {
      success: false,
      error: error.message,
      section: DEFAULT_SECTION,
      confidence: 0,
    };
  }
}

export async function segmentAndClassifyComplete(documentBuffer, metadata = {}) {
  console.log("[ArticleSegmentation] Starting complete segmentation process...");

  try {
    const segmentResult = await segmentArticles(documentBuffer, metadata);

    if (!segmentResult.success) {
      return segmentResult;
    }

    const articlesWithSections = await Promise.all(
      segmentResult.segmentation.articles.map(async (article) => {
        const contentText = `${article.title} ${article.contentPreview}`;
        const detectedSection = classifyArticleSectionSync(contentText);

        if (detectedSection !== DEFAULT_SECTION) {
          return {
            ...article,
            detectedSection,
            sectionConfidence: 85,
            classificationMethod: "pattern",
          };
        }

        return {
          ...article,
          detectedSection: "General",
          sectionConfidence: 0,
          classificationMethod: "fallback",
        };
      })
    );

    return {
      success: true,
      segmentation: {
        ...segmentResult.segmentation,
        articles: articlesWithSections,
      },
      metadata,
      processingTime: "async_segmentation_complete",
    };
  } catch (error) {
    console.error(
      "[ArticleSegmentation] Complete segmentation failed:",
      error.message
    );
    return {
      success: false,
      error: error.message,
      segmentation: {
        articlesFound: 0,
        articles: [],
        totalPages: 0,
        analysisQuality: "failed",
      },
    };
  }
}
