-- GatiVani Extracted Texts Storage
-- Stores raw OCR-extracted text from documents for efficient retrieval and reuse
-- Created: 2026-05-24

-- ============================================================================
-- EXTRACTED_TEXTS TABLE
-- ============================================================================
-- Stores raw text extracted from documents via OCR
-- Each extraction is preserved to avoid re-processing and reduce API costs
CREATE TABLE IF NOT EXISTS public.extracted_texts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Source document information
  filename TEXT NOT NULL,
  mime_type TEXT,
  file_size INT,

  -- Extracted content
  text TEXT NOT NULL,

  -- Extraction metadata
  language TEXT DEFAULT 'te',
  source TEXT DEFAULT 'ocr',
  confidence FLOAT DEFAULT 0.8,

  -- Audit timestamps
  extracted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for efficient queries
CREATE INDEX idx_extracted_texts_filename
  ON public.extracted_texts (filename);

CREATE INDEX idx_extracted_texts_language
  ON public.extracted_texts (language);

CREATE INDEX idx_extracted_texts_extracted_at
  ON public.extracted_texts (extracted_at DESC);

CREATE INDEX idx_extracted_texts_source
  ON public.extracted_texts (source);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on the table
ALTER TABLE public.extracted_texts ENABLE ROW LEVEL SECURITY;

-- Allow public read access to extracted texts (for retrieval by API)
CREATE POLICY "extracted_texts_select_public"
  ON public.extracted_texts
  FOR SELECT
  USING (TRUE);

-- Allow authenticated users to insert new extracted texts
CREATE POLICY "extracted_texts_insert_authenticated"
  ON public.extracted_texts
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Allow authenticated users to update their own extractions
CREATE POLICY "extracted_texts_update_authenticated"
  ON public.extracted_texts
  FOR UPDATE
  WITH CHECK (auth.role() = 'authenticated');

-- Allow authenticated users to delete their own extractions
CREATE POLICY "extracted_texts_delete_authenticated"
  ON public.extracted_texts
  FOR DELETE
  USING (auth.role() = 'authenticated');

-- ============================================================================
-- COMMENTS (Documentation)
-- ============================================================================

COMMENT ON TABLE public.extracted_texts IS
  'Stores raw text extracted from documents via OCR. Each extraction preserves the original text to avoid re-processing.';

COMMENT ON COLUMN public.extracted_texts.filename IS
  'Original document filename for reference and tracking';

COMMENT ON COLUMN public.extracted_texts.mime_type IS
  'MIME type of the source document (e.g., application/pdf, image/jpeg)';

COMMENT ON COLUMN public.extracted_texts.file_size IS
  'Size of the source document in bytes';

COMMENT ON COLUMN public.extracted_texts.text IS
  'Raw text extracted from the document via OCR';

COMMENT ON COLUMN public.extracted_texts.language IS
  'Language code of the extracted text (e.g., te for Telugu, hi for Hindi)';

COMMENT ON COLUMN public.extracted_texts.source IS
  'Source of the extraction (e.g., ocr for OCR processing)';

COMMENT ON COLUMN public.extracted_texts.confidence IS
  'OCR confidence score (0.0-1.0 scale)';
