import express from "express";
import multer from "multer";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";
import { maxPagesForTier } from "../lib/subscription-tiers.js";
import { extractPdfText as extractPdfTextByPageCap } from "../lib/pdf-extractor.js";
import { generateScript as generateWithGemini } from "../services/gemini-service.js";
import { generateTeluguAudioDataUrl } from "../services/azure-tts-service.js";
import { requireActiveSubscription } from "../middleware/subscription.js";
import { env } from "../config/env.js";
import { preprocessDocument, extractArticleContent } from "../services/stage1-preprocessing.js";
import {
  processArticleImage,
  cleanArticleText,
  enhanceTextForReadability,
} from "../services/stage2-datacleaning.js";
import {
  verifyTextQuality,
  verifyImageQuality,
  generateArticleAudio,
  calculateFinalQualityScore,
  finalizeArticleOutput,
} from "../services/stage3-postprocessing.js";
import { segmentArticles } from "../services/article-segmentation-service.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Save uploads to <root>/uploads/ so /uploads static route can serve them
const uploadsDir = path.resolve(__dirname, "../../../uploads");
if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 25 * 1024 * 1024, files: 1 },
});

export const documentsRouter = express.Router();

/**
 * POST /api/documents/process
 *
 * NEW: Multi-stage processing pipeline
 * - Stage 1: Pre-processing (layout analysis)
 * - Stage 2: Data cleaning & enhancement
 * - Stage 3: Post-processing & audio generation
 *
 * Accepts: multipart/form-data  { document: <file> }
 * Headers: X-Subscription-Tier: free | standard | premium
 *
 * Returns:
 * {
 *   ok: true,
 *   title: string,
 *   summary: string,
 *   category: string,
 *   storageUrl: string,
 *   audioUrl: string (if audio generation successful),
 *   pipeline: {
 *     stage1: { analysis, metadata },
 *     stage2: { image, text, quality },
 *     stage3: { verification, qualityScore }
 *   },
 *   model: string,
 *   subscription: { tier, active },
 *   limits: { maxPages, totalPages, processedPages, truncated }
 * }
 */
documentsRouter.post(
  "/process",
  requireActiveSubscription,
  upload.single("document"),
  async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({
          error: "missing_file",
          message: 'Expected multipart field "document".',
        });
      }

      const { tier, active } = req.subscription;
      const cap = maxPagesForTier(tier);
      const mime = req.file.mimetype || "";
      const originalName = req.file.originalname || "upload";
      const startTime = Date.now();

      // ── Persist file to disk ────────────────────────────────────────────────
      const safeFilename = `${Date.now()}_${originalName.replace(/[^a-zA-Z0-9._-]/g, "_")}`;
      const savedPath = path.join(uploadsDir, safeFilename);
      await fs.promises.writeFile(savedPath, req.file.buffer);
      const storageUrl = `${env.publicOrigin}/uploads/${safeFilename}`;
      console.log(`[process] Saved upload → ${savedPath}`);

      // ── STAGE 1: Pre-Processing ─────────────────────────────────────────────
      console.log("[process] ▶ Stage 1: Pre-Processing");
      let stage1Result = null;
      try {
        stage1Result = await preprocessDocument(
          req.file.buffer,
          mime || "application/pdf",
          originalName
        );

        // Extract article content from analyzed document
        if (stage1Result.success) {
          const contentResult = await extractArticleContent(stage1Result);
          stage1Result.articleContent = contentResult;
        }
      } catch (err) {
        console.warn("[process] Stage 1 failed, using fallback:", err.message);
        stage1Result = {
          success: false,
          error: err.message,
          analysis: {
            hasCoverImage: false,
            hasMainText: true,
            quality: { readability: "unknown" },
          },
          metadata: { publication: null, date: null, author: null },
          articleContent: { success: false, articleText: "" },
        };
      }

      // ── SEGMENTATION: Detect articles in newspaper ──────────────────────────
      console.log("[process] ▶ Article Segmentation");
      let segmentationResult = null;
      let articles = [];
      let processedArticles = [];
      let failedArticles = [];

      try {
        segmentationResult = await segmentArticles(req.file.buffer, {
          mimeType: mime,
          filename: originalName,
        });

        if (segmentationResult.success && segmentationResult.segmentation?.articles?.length > 0) {
          articles = segmentationResult.segmentation.articles;
          console.log(`[process] Segmented ${articles.length} articles from newspaper`);

          // ── STAGE 2 & 3: Process each article independently ──────────────────
          console.log(`[process] ▶ Processing ${articles.length} articles through Stages 2 & 3`);

          processedArticles = await Promise.all(
            articles.map(async (article) => {
              try {
                console.log(`[process] Processing article: "${article.title}"`);

                // For each article, we'll use the full document and article metadata
                // In production, extractArticleImage() would crop the specific article region
                const articleBuffer = req.file.buffer;

                // ── Stage 2: Data Cleaning ──────────────────────────────────────
                let stage2 = { success: false, text: { enhanced: "" } };
                try {
                  // For segmented articles, we use the contentPreview as the article text
                  const articleText = `${article.title}\n${article.contentPreview || ""}`;

                  // Image processing (uses full document in segmentation context)
                  const imageResult = await processArticleImage(articleBuffer);

                  // Text cleaning
                  const cleanResult = articleText
                    ? await cleanArticleText(articleText)
                    : { success: false, articleText: "" };

                  // Text enhancement
                  const enhanceResult = cleanResult.success
                    ? await enhanceTextForReadability(cleanResult.articleText)
                    : { success: false, articleText: cleanResult.articleText };

                  stage2 = {
                    success: imageResult.success && cleanResult.success,
                    image: imageResult.analysis,
                    text: {
                      original: articleText,
                      cleaned: cleanResult.articleText,
                      enhanced: enhanceResult.articleText,
                    },
                    quality: {
                      imageReadability: imageResult.analysis?.readability,
                      textCleaned: cleanResult.success,
                      textEnhanced: enhanceResult.success,
                    },
                  };
                } catch (err) {
                  console.warn(`[process] Stage 2 failed for "${article.title}":`, err.message);
                  stage2 = { success: false, error: err.message, text: { enhanced: "" } };
                }

                // ── Stage 3: Post-Processing & Audio Generation ────────────────
                let stage3 = { success: false, qualityScore: 0 };
                let audioUrl = "";

                try {
                  const enhancedText = stage2.text?.enhanced || "";

                  if (enhancedText.length > 0) {
                    // Verify text quality
                    const textVerif = await verifyTextQuality(enhancedText);

                    // Verify image quality
                    const imageVerif = await verifyImageQuality(articleBuffer);

                    // Generate audio
                    const audioGen = await generateArticleAudio(enhancedText, "te-IN");
                    audioUrl = audioGen.audioUrl || "";

                    // Calculate quality score
                    const qualityScore = await calculateFinalQualityScore(
                      textVerif.verification,
                      imageVerif.verification,
                      audioGen.success
                    );

                    stage3 = {
                      success: audioGen.success,
                      qualityScore,
                      audioGenerated: audioGen.success,
                    };
                  } else {
                    console.warn(`[process] Stage 3: No text for article "${article.title}"`);
                  }
                } catch (err) {
                  console.warn(`[process] Stage 3 failed for "${article.title}":`, err.message);
                  stage3 = { success: false, qualityScore: 0, error: err.message };
                }

                // Return processed article with all stages
                return {
                  id: article.id,
                  title: article.title,
                  section: article.section || article.detectedSection || "General",
                  preview: article.contentPreview?.slice(0, 200),
                  audioUrl,
                  qualityScore: stage3.qualityScore || 0,
                  status: stage3.success ? "completed" : "failed",
                  page: article.page,
                  position: article.position,
                  confidence: article.confidence,
                  stages: { stage2, stage3 },
                };
              } catch (err) {
                console.error(`[process] Failed to process article "${article.title}":`, err.message);
                failedArticles.push({
                  id: article.id,
                  title: article.title,
                  error: err.message,
                });

                return {
                  id: article.id,
                  title: article.title,
                  section: article.section || article.detectedSection || "General",
                  preview: article.contentPreview?.slice(0, 200),
                  audioUrl: "",
                  qualityScore: 0,
                  status: "failed",
                  error: err.message,
                };
              }
            })
          );

          // Separate successful and failed articles
          failedArticles = processedArticles.filter((a) => a.status === "failed");
        } else {
          console.warn("[process] Segmentation failed, falling back to single-article mode");
        }
      } catch (err) {
        console.warn("[process] Segmentation error:", err.message);
      }

      // ── Fallback: Single-article mode if segmentation failed ─────────────────
      if (articles.length === 0) {
        console.log("[process] ▶ Fallback: Single-Article Processing");

        try {
          const articleText = stage1Result.articleContent?.articleText || "";
          const imageBuffer = req.file.buffer;

          // ── Stage 2: Data Cleaning ──────────────────────────────────────────
          const imageResult = await processArticleImage(imageBuffer);
          const cleanResult = articleText
            ? await cleanArticleText(articleText)
            : { success: false, articleText: "" };
          const enhanceResult = cleanResult.success
            ? await enhanceTextForReadability(cleanResult.articleText)
            : { success: false, articleText: cleanResult.articleText };

          const stage2Result = {
            success: imageResult.success && cleanResult.success,
            text: { enhanced: enhanceResult.articleText },
          };

          // ── Stage 3: Post-Processing ────────────────────────────────────────
          let audioUrl = "";
          let qualityScore = 0;

          try {
            const enhancedText = stage2Result.text?.enhanced || "";

            if (enhancedText.length > 0) {
              const textVerif = await verifyTextQuality(enhancedText);
              const imageVerif = await verifyImageQuality(imageBuffer);
              const audioGen = await generateArticleAudio(enhancedText, "te-IN");
              audioUrl = audioGen.audioUrl || "";
              qualityScore = await calculateFinalQualityScore(
                textVerif.verification,
                imageVerif.verification,
                audioGen.success
              );
            }
          } catch (err) {
            console.warn("[process] Fallback Stage 3 failed:", err.message);
          }

          const title = deriveTitle(articleText.slice(0, 1000) || originalName, originalName);
          const section = deriveCategory(articleText);

          processedArticles = [
            {
              id: "article_1",
              title,
              section,
              preview: articleText.slice(0, 200),
              audioUrl,
              qualityScore,
              status: audioUrl ? "completed" : "failed",
              page: 1,
            },
          ];
        } catch (err) {
          console.error("[process] Fallback processing failed:", err.message);
          processedArticles = [];
        }
      }

      // ── Derive newspaper metadata ───────────────────────────────────────────
      const newspaperTitle = stage1Result?.metadata?.publication || originalName || "Newspaper";
      const publicationDate = stage1Result?.metadata?.date || new Date().toISOString().split("T")[0];

      let totalPages = 1;
      let processedPages = 1;
      let truncated = false;

      // Try to get page info if it's a PDF
      if (mime === "application/pdf" || originalName.toLowerCase().endsWith(".pdf")) {
        try {
          const extracted = await extractPdfTextByPageCap(req.file.buffer, cap);
          totalPages = extracted.totalPages;
          processedPages = extracted.processedPages;
          truncated = totalPages > processedPages;
        } catch {
          // Ignore PDF extraction errors
        }
      }

      const processingTime = Math.round((Date.now() - startTime) / 1000); // seconds

      // ── Build response ──────────────────────────────────────────────────────
      return res.json({
        ok: true,
        newspaper: {
          id: `newspaper_${Date.now()}`,
          title: newspaperTitle,
          date: publicationDate,
          storageUrl,
        },
        articles: processedArticles.map((article) => ({
          id: article.id,
          title: article.title,
          section: article.section,
          preview: article.preview,
          audioUrl: article.audioUrl,
          qualityScore: Math.round(article.qualityScore * 100) || 0,
          status: article.status,
          // Optional: include detailed stage results if needed
          // stages: article.stages,
        })),
        summary: {
          totalArticles: articles.length || 1,
          processedArticles: processedArticles.filter((a) => a.status === "completed").length,
          failedArticles: failedArticles.length,
          processingTime,
        },
        // Backward compatibility fields
        model: env.geminiModel,
        subscription: { tier, active },
        limits: { maxPages: cap, totalPages, processedPages, truncated },
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      console.error("[documents/process]", err);
      return res.status(500).json({ error: "process_failed", message });
    }
  }
);

/**
 * POST /api/documents/synthesize
 *
 * Accepts: { text: string, language?: "te-IN" | "hi-IN" | "en-IN" }
 *
 * Generates natural audio using Microsoft Azure Text-to-Speech
 * Returns:
 * {
 *   ok: true,
 *   audioUrl: string  // data URL with base64-encoded MP3 audio
 * }
 */
documentsRouter.post(
  "/synthesize",
  requireActiveSubscription,
  express.json(),
  async (req, res) => {
    try {
      const { text, language = "te-IN" } = req.body;

      if (!text || typeof text !== "string") {
        return res.status(400).json({
          error: "missing_text",
          message: 'Expected "text" field in request body.',
        });
      }

      if (text.trim().length === 0) {
        return res.status(400).json({
          error: "empty_text",
          message: "Text cannot be empty.",
        });
      }

      console.log(
        `[synthesize] Generating ${language} audio for ${text.length} chars`
      );

      const audioUrl = await generateTeluguAudioDataUrl(text, language);

      return res.json({
        ok: true,
        audioUrl,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      console.error("[documents/synthesize]", err);
      return res.status(500).json({ error: "synthesis_failed", message });
    }
  }
);

// ── Helpers ──────────────────────────────────────────────────────────────────

function deriveTitle(summary, fallbackFilename) {
  if (!summary) return fallbackFilename;
  // Use the first non-empty line, truncated to 80 chars
  const firstLine = summary.split("\n").map((l) => l.trim()).find((l) => l.length > 0);
  if (!firstLine) return fallbackFilename;
  return firstLine.length > 80 ? firstLine.slice(0, 77) + "..." : firstLine;
}

const CATEGORY_PATTERNS = [
  { pattern: /రాజకీయ|పార్టీ|ఎన్నిక|ప్రభుత్వ|మంత్రి|cm|chief minister/i, label: "Politics" },
  { pattern: /క్రికెట్|ఫుట్‌బాల్|ఆటలు|క్రీడ|sports|cricket|ipl/i,        label: "Sports" },
  { pattern: /వ్యాపార|మార్కెట్|సెన్సెక్స్|నిఫ్టీ|economy|stock|market/i,   label: "Business" },
  { pattern: /సినిమా|చిత్రం|నటుడు|నటి|actor|film|tollywood/i,              label: "Entertainment" },
  { pattern: /ఆరోగ్య|వైద్య|వ్యాధి|hospital|health|covid/i,                 label: "Health" },
  { pattern: /విద్య|పాఠశాల|కళాశాల|university|education|exam/i,             label: "Education" },
];

function deriveCategory(summary) {
  if (!summary) return "News";
  for (const { pattern, label } of CATEGORY_PATTERNS) {
    if (pattern.test(summary)) return label;
  }
  return "News";
}
