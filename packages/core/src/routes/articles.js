import express from "express";
import { createClient } from "@supabase/supabase-js";
import { authRequired } from "../middleware/auth.js";
import {
  markArticleAsRead,
  toggleArticleFavorite,
  updateArticleNotes,
  getUserReadingHistory,
  getUserFavoriteArticles,
  searchArticles,
  filterBySection,
  getAvailableSections,
  sortArticles,
  getNewspapersWithCounts
} from "../database/article-repository.js";

export const articlesRouter = express.Router();

// Initialize Supabase client from environment
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.warn("[articles router] SUPABASE_URL or SUPABASE_ANON_KEY not configured");
}

const supabase = supabaseUrl && supabaseKey
  ? createClient(supabaseUrl, supabaseKey)
  : null;

/**
 * POST /api/articles/:articleId/mark-read
 *
 * Mark an article as read by the authenticated user.
 * Stores timestamp when user accessed/played the article.
 *
 * Headers:
 *   Authorization: Bearer <jwt_token>
 *
 * Request Body (optional):
 *   {
 *     "readAt": "2026-05-23T12:00:00Z"  // Optional: ISO timestamp. Defaults to now()
 *   }
 *
 * Returns:
 *   {
 *     "ok": true,
 *     "data": {
 *       "id": "uuid",
 *       "user_id": "uuid",
 *       "article_id": "uuid",
 *       "read_at": "2026-05-23T12:00:00Z",
 *       "favorite": false,
 *       "notes": null,
 *       "created_at": "2026-05-23T12:00:00Z"
 *     }
 *   }
 */
articlesRouter.post("/:articleId/mark-read", authRequired, async (req, res) => {
  if (!supabase) {
    return res.status(503).json({
      error: "service_unavailable",
      message: "Supabase not configured"
    });
  }

  const { articleId } = req.params;
  const { readAt } = req.body || {};
  const userId = req.userId;

  if (!articleId || !userId) {
    return res.status(400).json({
      error: "invalid_request",
      message: "articleId and userId (from token) required"
    });
  }

  try {
    // Upsert with optional custom timestamp
    const timestamp = readAt ? new Date(readAt).toISOString() : new Date().toISOString();
    const { data: userArticle, error } = await supabase
      .from('user_articles')
      .upsert({
        user_id: userId,
        article_id: articleId,
        read_at: timestamp
      }, { onConflict: 'user_id,article_id' })
      .select()
      .single();

    if (error) {
      console.error("[mark-read] Database error:", error);
      return res.status(500).json({
        error: "database_error",
        message: error.message
      });
    }

    res.json({ ok: true, data: userArticle });
  } catch (err) {
    console.error("[mark-read] Error:", err);
    res.status(500).json({
      error: "internal_error",
      message: err.message
    });
  }
});

/**
 * POST /api/articles/:articleId/toggle-favorite
 *
 * Toggle favorite status for an article.
 *
 * Headers:
 *   Authorization: Bearer <jwt_token>
 *
 * Request Body:
 *   {
 *     "isFavorite": true | false
 *   }
 *
 * Returns:
 *   {
 *     "ok": true,
 *     "data": {
 *       "id": "uuid",
 *       "user_id": "uuid",
 *       "article_id": "uuid",
 *       "favorite": true,
 *       "read_at": "2026-05-23T12:00:00Z",
 *       "notes": null,
 *       "created_at": "2026-05-23T12:00:00Z"
 *     }
 *   }
 */
articlesRouter.post("/:articleId/toggle-favorite", authRequired, async (req, res) => {
  if (!supabase) {
    return res.status(503).json({
      error: "service_unavailable",
      message: "Supabase not configured"
    });
  }

  const { articleId } = req.params;
  const { isFavorite } = req.body || {};
  const userId = req.userId;

  if (!articleId || userId === undefined || isFavorite === undefined) {
    return res.status(400).json({
      error: "invalid_request",
      message: "articleId, userId (from token), and isFavorite (boolean) required"
    });
  }

  try {
    const userArticle = await toggleArticleFavorite(supabase, userId, articleId, isFavorite);
    res.json({ ok: true, data: userArticle });
  } catch (err) {
    console.error("[toggle-favorite] Error:", err);
    res.status(500).json({
      error: "database_error",
      message: err.message
    });
  }
});

/**
 * POST /api/articles/:articleId/notes
 *
 * Add or update notes/annotations for an article.
 *
 * Headers:
 *   Authorization: Bearer <jwt_token>
 *
 * Request Body:
 *   {
 *     "notes": "User's annotations or bookmarks"
 *   }
 *
 * Returns:
 *   {
 *     "ok": true,
 *     "data": {
 *       "id": "uuid",
 *       "user_id": "uuid",
 *       "article_id": "uuid",
 *       "notes": "User's annotations...",
 *       "favorite": false,
 *       "read_at": "2026-05-23T12:00:00Z",
 *       "created_at": "2026-05-23T12:00:00Z"
 *     }
 *   }
 */
articlesRouter.post("/:articleId/notes", authRequired, async (req, res) => {
  if (!supabase) {
    return res.status(503).json({
      error: "service_unavailable",
      message: "Supabase not configured"
    });
  }

  const { articleId } = req.params;
  const { notes } = req.body || {};
  const userId = req.userId;

  if (!articleId || userId === undefined || notes === undefined) {
    return res.status(400).json({
      error: "invalid_request",
      message: "articleId, userId (from token), and notes required"
    });
  }

  try {
    const userArticle = await updateArticleNotes(supabase, userId, articleId, notes);
    res.json({ ok: true, data: userArticle });
  } catch (err) {
    console.error("[notes] Error:", err);
    res.status(500).json({
      error: "database_error",
      message: err.message
    });
  }
});

/**
 * GET /api/user/reading-history
 *
 * Fetch reading history for authenticated user (previously read articles).
 * Supports pagination with limit and offset.
 *
 * Headers:
 *   Authorization: Bearer <jwt_token>
 *
 * Query Parameters:
 *   ?limit=50      - Max articles per page (default: 50)
 *   ?offset=0      - Pagination offset (default: 0)
 *   ?favoritesOnly=true  - Only return favorite articles (optional)
 *
 * Returns:
 *   {
 *     "ok": true,
 *     "data": [
 *       {
 *         "id": "uuid",
 *         "user_id": "uuid",
 *         "article_id": "uuid",
 *         "read_at": "2026-05-23T12:00:00Z",
 *         "favorite": true,
 *         "notes": null,
 *         "created_at": "2026-05-23T12:00:00Z",
 *         "articles": {
 *           "id": "uuid",
 *           "title": "Article Title",
 *           "section": "News",
 *           "image_url": "https://...",
 *           "audio_url": "https://...",
 *           "quality_score": 0.95,
 *           "newspaper_id": "uuid"
 *         }
 *       }
 *     ],
 *     "pagination": {
 *       "limit": 50,
 *       "offset": 0,
 *       "total": 125
 *     }
 *   }
 */
articlesRouter.get("/user/reading-history", authRequired, async (req, res) => {
  if (!supabase) {
    return res.status(503).json({
      error: "service_unavailable",
      message: "Supabase not configured"
    });
  }

  const userId = req.userId;
  const limit = Math.min(Math.max(parseInt(req.query.limit) || 50, 1), 100);
  const offset = Math.max(parseInt(req.query.offset) || 0, 0);
  const favoritesOnly = req.query.favoritesOnly === 'true';

  try {
    const articles = await getUserReadingHistory(
      supabase,
      userId,
      { limit, offset, favoritesOnly }
    );

    // Get total count for pagination metadata
    let countQuery = supabase
      .from('user_articles')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId);

    if (favoritesOnly) {
      countQuery = countQuery.eq('favorite', true);
    }

    const { count } = await countQuery;

    res.json({
      ok: true,
      data: articles,
      pagination: {
        limit,
        offset,
        total: count || 0
      }
    });
  } catch (err) {
    console.error("[reading-history] Error:", err);
    res.status(500).json({
      error: "database_error",
      message: err.message
    });
  }
});

/**
 * GET /api/user/favorites
 *
 * Fetch favorite articles for authenticated user.
 * Convenience endpoint - equivalent to /api/user/reading-history?favoritesOnly=true
 *
 * Headers:
 *   Authorization: Bearer <jwt_token>
 *
 * Query Parameters:
 *   ?limit=50  - Max articles per page (default: 50)
 *   ?offset=0  - Pagination offset (default: 0)
 *
 * Returns: Same format as reading-history endpoint
 */
articlesRouter.get("/user/favorites", authRequired, async (req, res) => {
  if (!supabase) {
    return res.status(503).json({
      error: "service_unavailable",
      message: "Supabase not configured"
    });
  }

  const userId = req.userId;
  const limit = Math.min(Math.max(parseInt(req.query.limit) || 50, 1), 100);
  const offset = Math.max(parseInt(req.query.offset) || 0, 0);

  try {
    const articles = await getUserFavoriteArticles(supabase, userId, limit, offset);

    // Get total count for pagination metadata
    const { count } = await supabase
      .from('user_articles')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('favorite', true);

    res.json({
      ok: true,
      data: articles,
      pagination: {
        limit,
        offset,
        total: count || 0
      }
    });
  } catch (err) {
    console.error("[favorites] Error:", err);
    res.status(500).json({
      error: "database_error",
      message: err.message
    });
  }
});

// ============================================================================
// SEARCH AND FILTERING ENDPOINTS
// ============================================================================

/**
 * GET /api/articles/search?q=keyword&limit=20&offset=0
 *
 * Search articles by keyword in title and content preview.
 * Uses case-insensitive ILIKE search for flexible matching.
 *
 * Query Parameters:
 *   ?q=<keyword>    - Search keyword/phrase (required)
 *   ?limit=20       - Results per page (default: 20, max: 100)
 *   ?offset=0       - Pagination offset (default: 0)
 *
 * Returns:
 *   {
 *     "articles": [...],
 *     "total": 150,
 *     "limit": 20,
 *     "offset": 0,
 *     "query": "cricket"
 *   }
 *
 * @example
 * GET /api/articles/search?q=cricket&limit=20&offset=0
 */
articlesRouter.get("/search", async (req, res) => {
  if (!supabase) {
    return res.status(503).json({
      error: "service_unavailable",
      message: "Supabase not configured"
    });
  }

  try {
    const { q, limit = 20, offset = 0 } = req.query;

    if (!q) {
      return res.status(400).json({
        error: "invalid_request",
        message: "Search query 'q' is required"
      });
    }

    const parsedLimit = Math.min(Math.max(parseInt(limit) || 20, 1), 100);
    const parsedOffset = Math.max(parseInt(offset) || 0, 0);

    const result = await searchArticles(supabase, q, parsedLimit, parsedOffset);

    if (result.success) {
      res.json({
        articles: result.data || [],
        query: q,
        limit: parsedLimit,
        offset: parsedOffset,
        total: result.data?.length || 0
      });
    } else {
      res.status(500).json({
        error: "search_failed",
        message: result.error
      });
    }
  } catch (error) {
    console.error("[search] Error:", error);
    res.status(500).json({
      error: "search_failed",
      message: error.message
    });
  }
});

/**
 * GET /api/articles/filter?section=Politics&limit=20&offset=0
 *
 * Filter articles by section/category.
 * Returns articles matching the specified section with pagination.
 *
 * Query Parameters:
 *   ?section=<name> - Section name (e.g., "Politics", "Sports", "Business") (required)
 *   ?limit=20       - Results per page (default: 20, max: 100)
 *   ?offset=0       - Pagination offset (default: 0)
 *
 * Returns:
 *   {
 *     "articles": [...],
 *     "total": 45,
 *     "section": "Sports",
 *     "limit": 20,
 *     "offset": 0
 *   }
 *
 * @example
 * GET /api/articles/filter?section=Sports&limit=20
 */
articlesRouter.get("/filter", async (req, res) => {
  if (!supabase) {
    return res.status(503).json({
      error: "service_unavailable",
      message: "Supabase not configured"
    });
  }

  try {
    const { section, limit = 20, offset = 0 } = req.query;

    if (!section) {
      return res.status(400).json({
        error: "invalid_request",
        message: "Section parameter is required"
      });
    }

    const parsedLimit = Math.min(Math.max(parseInt(limit) || 20, 1), 100);
    const parsedOffset = Math.max(parseInt(offset) || 0, 0);

    const result = await filterBySection(supabase, section, parsedLimit, parsedOffset);

    if (result.success) {
      res.json({
        articles: result.data || [],
        section,
        limit: parsedLimit,
        offset: parsedOffset,
        total: result.data?.length || 0
      });
    } else {
      res.status(500).json({
        error: "filter_failed",
        message: result.error
      });
    }
  } catch (error) {
    console.error("[filter] Error:", error);
    res.status(500).json({
      error: "filter_failed",
      message: error.message
    });
  }
});

/**
 * GET /api/articles/sort?by=quality&limit=20&offset=0
 *
 * Sort articles by quality score or publication date.
 * Returns articles in descending order (highest quality/newest first).
 *
 * Query Parameters:
 *   ?by=<criteria>  - Sort criteria: 'quality' or 'date' (default: 'date')
 *   ?limit=20       - Results per page (default: 20, max: 100)
 *   ?offset=0       - Pagination offset (default: 0)
 *
 * Returns:
 *   {
 *     "articles": [...],  // Sorted by quality_score DESC or created_at DESC
 *     "total": 500,
 *     "sortBy": "quality",
 *     "limit": 20,
 *     "offset": 0
 *   }
 *
 * @example
 * GET /api/articles/sort?by=quality&limit=20
 * GET /api/articles/sort?by=date&offset=20
 */
articlesRouter.get("/sort", async (req, res) => {
  if (!supabase) {
    return res.status(503).json({
      error: "service_unavailable",
      message: "Supabase not configured"
    });
  }

  try {
    const { by = "date", limit = 20, offset = 0 } = req.query;

    if (!["quality", "date"].includes(by)) {
      return res.status(400).json({
        error: "invalid_request",
        message: "Sort parameter 'by' must be 'quality' or 'date'"
      });
    }

    const parsedLimit = Math.min(Math.max(parseInt(limit) || 20, 1), 100);
    const parsedOffset = Math.max(parseInt(offset) || 0, 0);

    const result = await sortArticles(supabase, by, parsedLimit, parsedOffset);

    if (result.success) {
      res.json({
        articles: result.data || [],
        sortBy: by,
        limit: parsedLimit,
        offset: parsedOffset,
        total: result.data?.length || 0
      });
    } else {
      res.status(500).json({
        error: "sort_failed",
        message: result.error
      });
    }
  } catch (error) {
    console.error("[sort] Error:", error);
    res.status(500).json({
      error: "sort_failed",
      message: error.message
    });
  }
});

/**
 * GET /api/articles/sections
 *
 * Get all available article sections with article counts.
 * Useful for populating filter UI and showing section stats.
 *
 * Returns:
 *   [
 *     { "section": "Politics", "count": 45 },
 *     { "section": "Sports", "count": 78 },
 *     { "section": "Business", "count": 32 },
 *     { "section": "Health", "count": 25 }
 *   ]
 *
 * @example
 * GET /api/articles/sections
 */
articlesRouter.get("/sections", async (req, res) => {
  if (!supabase) {
    return res.status(503).json({
      error: "service_unavailable",
      message: "Supabase not configured"
    });
  }

  try {
    const result = await getAvailableSections(supabase);
    if (result.success) {
      res.json(result.data || []);
    } else {
      res.status(500).json({
        error: "sections_failed",
        message: result.error
      });
    }
  } catch (error) {
    console.error("[sections] Error:", error);
    res.status(500).json({
      error: "sections_failed",
      message: error.message
    });
  }
});

/**
 * GET /api/newspapers
 *
 * Get all newspapers with article counts.
 * Returns list of newspaper editions with total articles per newspaper.
 *
 * Returns:
 *   [
 *     {
 *       "id": "uuid",
 *       "title": "The Hindu",
 *       "publication_date": "2026-05-23",
 *       "language": "en",
 *       "article_count": 45
 *     },
 *     {
 *       "id": "uuid",
 *       "title": "Times of India",
 *       "publication_date": "2026-05-23",
 *       "language": "en",
 *       "article_count": 67
 *     }
 *   ]
 *
 * @example
 * GET /api/newspapers
 */
articlesRouter.get("/", async (req, res) => {
  if (!supabase) {
    return res.status(503).json({
      error: "service_unavailable",
      message: "Supabase not configured"
    });
  }

  try {
    const result = await getNewspapersWithCounts(supabase);
    if (result.success) {
      res.json(result.data || []);
    } else {
      res.status(500).json({
        error: "newspapers_failed",
        message: result.error
      });
    }
  } catch (error) {
    console.error("[newspapers] Error:", error);
    res.status(500).json({
      error: "newspapers_failed",
      message: error.message
    });
  }
});
