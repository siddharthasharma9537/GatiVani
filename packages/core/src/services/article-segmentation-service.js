/**
 * Article Segmentation Service
 * Pattern-based section classification. For newspaper documents, falls
 * back to single-article mode (the whole document treated as one article).
 */

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
  console.log("[ArticleSegmentation] Falling back to single-article mode...");

  // Triggers the single-article processing path in documents.js
  return {
    success: false,
    error: "segmentation_not_available",
    segmentation: {
      articlesFound: 1,
      articles: [
        {
          id: "article_1",
          title: metadata.filename || "Document",
          section: "General",
          contentPreview: "Full document processed as single article via Sarvam OCR",
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

export function classifyArticleSectionSync(content) {
  for (const [section, pattern] of Object.entries(SECTION_PATTERNS)) {
    if (pattern.test(content)) {
      return section;
    }
  }
  return DEFAULT_SECTION;
}
