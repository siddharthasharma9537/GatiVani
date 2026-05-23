import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const pdfParse = require("pdf-parse");

/**
 * Extract text from a PDF buffer, honouring a page cap per subscription tier.
 * Falls back to proportional truncation when page form-feeds are absent.
 *
 * Canonical name: pdf-extractor.js
 * (pdfExtract.js and pdf_extractor.js are backward-compat re-exports)
 *
 * @param {Buffer} buffer - Raw PDF file bytes
 * @param {number} maxPages - Maximum pages to process (from tier config)
 * @returns {Promise<{ totalPages: number; processedPages: number; text: string }>}
 */
export async function extractPdfText(buffer, maxPages) {
  const data = await pdfParse(buffer);
  const totalPages = Math.max(1, data.numpages || 1);
  const processedPages = Math.min(totalPages, Math.max(1, maxPages));
  let text = String(data.text || "");

  const parts = text.split(/\f+/).filter((p) => p.trim().length > 0);
  if (parts.length > 1) {
    text = parts.slice(0, processedPages).join("\n\n").trim();
  } else if (totalPages > processedPages && text.length > 0) {
    const ratio = processedPages / totalPages;
    const truncated = text.slice(0, Math.max(1, Math.floor(text.length * ratio))).trim();
    text = `${truncated}\n\n[Content truncated: processed ${processedPages} of ${totalPages} pages. Upgrade your plan for full access.]`;
  }

  return { totalPages, processedPages, text };
}

// Backward-compat alias — callers using extractPdfTextByPageCap still work.
export const extractPdfTextByPageCap = extractPdfText;
