-- GatiVani Article Storage Schema
-- Defines tables for managing newspaper issues, articles, and user reading history
-- Created: 2026-05-23

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- NEWSPAPERS TABLE
-- ============================================================================
-- Stores metadata for newspaper issues/editions
-- Each newspaper represents a single issue published on a specific date
CREATE TABLE IF NOT EXISTS public.newspapers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Newspaper identification
  title TEXT NOT NULL,
  publication_date DATE NOT NULL,
  issue_number INT,
  language TEXT NOT NULL DEFAULT 'en',

  -- Storage reference
  storage_url TEXT,

  -- Audit timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index for efficient date-based queries
CREATE INDEX idx_newspapers_publication_date
  ON public.newspapers (publication_date DESC);

-- Index for language filtering
CREATE INDEX idx_newspapers_language
  ON public.newspapers (language);

-- ============================================================================
-- ARTICLES TABLE
-- ============================================================================
-- Stores individual articles extracted from newspapers
-- Each article belongs to exactly one newspaper
CREATE TABLE IF NOT EXISTS public.articles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Foreign key reference
  newspaper_id UUID NOT NULL REFERENCES public.newspapers(id) ON DELETE CASCADE,

  -- Article content
  title TEXT NOT NULL,
  content_preview TEXT,
  full_content TEXT,

  -- Article organization
  section TEXT,
  page_number INT,

  -- Position metadata (x, y, width, height as JSON)
  position_json JSONB,

  -- Media assets
  image_url TEXT,
  audio_url TEXT,

  -- Quality and processing
  quality_score FLOAT DEFAULT 0.0,
  processing_status TEXT DEFAULT 'pending',

  -- Audit timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for efficient article queries
CREATE INDEX idx_articles_newspaper_id
  ON public.articles (newspaper_id);

CREATE INDEX idx_articles_section
  ON public.articles (section);

-- Index for ranking articles by quality score (descending)
CREATE INDEX idx_articles_quality_score_desc
  ON public.articles (quality_score DESC);

-- Index for finding articles by processing status
CREATE INDEX idx_articles_processing_status
  ON public.articles (processing_status);

-- ============================================================================
-- USER_ARTICLES TABLE
-- ============================================================================
-- Tracks user interactions with articles (read history, favorites, notes)
-- Establishes many-to-many relationship between users and articles
CREATE TABLE IF NOT EXISTS public.user_articles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Foreign key references
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  article_id UUID NOT NULL REFERENCES public.articles(id) ON DELETE CASCADE,

  -- User interactions
  read_at TIMESTAMP WITH TIME ZONE,
  favorite BOOLEAN DEFAULT FALSE,
  notes TEXT,

  -- Audit timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

  -- Ensure unique user-article relationship
  UNIQUE(user_id, article_id)
);

-- Composite index for efficient user article lookups
CREATE INDEX idx_user_articles_user_id
  ON public.user_articles (user_id);

CREATE INDEX idx_user_articles_article_id
  ON public.user_articles (article_id);

-- Index for finding user's favorite articles
CREATE INDEX idx_user_articles_favorite
  ON public.user_articles (user_id, favorite)
  WHERE favorite = TRUE;

-- Index for finding recently read articles
CREATE INDEX idx_user_articles_read_at
  ON public.user_articles (user_id, read_at DESC)
  WHERE read_at IS NOT NULL;

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.newspapers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_articles ENABLE ROW LEVEL SECURITY;

-- NEWSPAPERS: Public read access, authenticated users can insert
CREATE POLICY "newspapers_select_public"
  ON public.newspapers
  FOR SELECT
  USING (TRUE);

CREATE POLICY "newspapers_insert_authenticated"
  ON public.newspapers
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "newspapers_update_authenticated"
  ON public.newspapers
  FOR UPDATE
  WITH CHECK (auth.role() = 'authenticated');

-- ARTICLES: Public read access, authenticated users can insert/update
CREATE POLICY "articles_select_public"
  ON public.articles
  FOR SELECT
  USING (TRUE);

CREATE POLICY "articles_insert_authenticated"
  ON public.articles
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "articles_update_authenticated"
  ON public.articles
  FOR UPDATE
  WITH CHECK (auth.role() = 'authenticated');

-- USER_ARTICLES: Users can only see and modify their own articles
CREATE POLICY "user_articles_select_own"
  ON public.user_articles
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "user_articles_insert_own"
  ON public.user_articles
  FOR INSERT
  WITH CHECK (auth.uid() = user_id AND auth.role() = 'authenticated');

CREATE POLICY "user_articles_update_own"
  ON public.user_articles
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_articles_delete_own"
  ON public.user_articles
  FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for newspapers.updated_at
CREATE TRIGGER update_newspapers_updated_at
BEFORE UPDATE ON public.newspapers
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- COMMENTS (Documentation)
-- ============================================================================

COMMENT ON TABLE public.newspapers IS
  'Stores newspaper/edition metadata. Each record represents a distinct publication date.';

COMMENT ON TABLE public.articles IS
  'Stores individual articles extracted from newspapers with content, metadata, and processing status.';

COMMENT ON TABLE public.user_articles IS
  'Tracks user interactions with articles including read status, favorites, and annotations.';

COMMENT ON COLUMN public.articles.position_json IS
  'JSON object containing article position on page: {x: number, y: number, w: number, h: number}';

COMMENT ON COLUMN public.articles.quality_score IS
  'Confidence score for content extraction and processing (0.0-1.0 scale)';

COMMENT ON COLUMN public.articles.processing_status IS
  'Processing status: pending, processing, completed, failed';

COMMENT ON COLUMN public.user_articles.read_at IS
  'Timestamp when user read/accessed the article (null if not yet read)';
