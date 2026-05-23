/**
 * Article Repository
 *
 * Helper module for managing article data operations with Supabase.
 * Provides high-level methods for newspaper and article CRUD operations.
 *
 * Usage:
 *   const { insertNewspaper, getArticlesByNewspaper } = require('./article-repository');
 *   const supabaseClient = createClient(url, key);
 *
 *   const newspaper = await insertNewspaper(supabaseClient, { title, publication_date, ... });
 *   const articles = await getArticlesByNewspaper(supabaseClient, newspaper.id);
 */

// ============================================================================
// NEWSPAPERS OPERATIONS
// ============================================================================

/**
 * Insert a new newspaper/edition into the database
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {Object} data - Newspaper data
 * @param {string} data.title - Newspaper title
 * @param {string} data.publication_date - Publication date (ISO format: YYYY-MM-DD)
 * @param {number} [data.issue_number] - Issue/edition number
 * @param {string} [data.language] - ISO language code (default: 'en')
 * @param {string} [data.storage_url] - URL to stored newspaper file/assets
 *
 * @returns {Promise<Object>} Inserted newspaper record with id, created_at, etc.
 * @throws {Error} If database operation fails
 *
 * @example
 * const newspaper = await insertNewspaper(supabase, {
 *   title: 'The Hindu',
 *   publication_date: '2026-05-23',
 *   issue_number: 145,
 *   language: 'en',
 *   storage_url: 'https://storage.example.com/the-hindu-2026-05-23'
 * });
 */
async function insertNewspaper(supabase, data) {
  const { data: newspaper, error } = await supabase
    .from('newspapers')
    .insert([{
      title: data.title,
      publication_date: data.publication_date,
      issue_number: data.issue_number || null,
      language: data.language || 'en',
      storage_url: data.storage_url || null
    }])
    .select()
    .single();

  if (error) throw error;
  return newspaper;
}

/**
 * Retrieve a newspaper by ID
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} newspaperId - Newspaper UUID
 *
 * @returns {Promise<Object|null>} Newspaper record or null if not found
 * @throws {Error} If database operation fails
 */
async function getNewspaperById(supabase, newspaperId) {
  const { data: newspaper, error } = await supabase
    .from('newspapers')
    .select()
    .eq('id', newspaperId)
    .single();

  if (error && error.code !== 'PGRST116') throw error;
  return newspaper || null;
}

/**
 * Get newspapers published within a date range
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} startDate - Start date (ISO format: YYYY-MM-DD)
 * @param {string} endDate - End date (ISO format: YYYY-MM-DD)
 * @param {string} [language] - Filter by language (optional)
 *
 * @returns {Promise<Array>} Array of newspaper records
 * @throws {Error} If database operation fails
 */
async function getNewspapersByDateRange(supabase, startDate, endDate, language = null) {
  let query = supabase
    .from('newspapers')
    .select()
    .gte('publication_date', startDate)
    .lte('publication_date', endDate)
    .order('publication_date', { ascending: false });

  if (language) {
    query = query.eq('language', language);
  }

  const { data: newspapers, error } = await query;
  if (error) throw error;
  return newspapers;
}

// ============================================================================
// ARTICLES OPERATIONS
// ============================================================================

/**
 * Insert multiple articles for a newspaper in a single operation
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} newspaperId - Parent newspaper UUID
 * @param {Array<Object>} articles - Array of article objects to insert
 * @param {string} articles[].title - Article title
 * @param {string} [articles[].content_preview] - Brief preview of content
 * @param {string} [articles[].full_content] - Complete article text
 * @param {string} [articles[].section] - Section/category (e.g., "Sports", "Politics")
 * @param {number} [articles[].page_number] - Page number in newspaper
 * @param {Object} [articles[].position_json] - Position coordinates {x, y, w, h}
 * @param {string} [articles[].image_url] - URL to article image/thumbnail
 * @param {string} [articles[].audio_url] - URL to TTS-generated audio
 * @param {number} [articles[].quality_score] - Content extraction confidence (0-1)
 * @param {string} [articles[].processing_status] - Status: pending, processing, completed, failed
 *
 * @returns {Promise<Array>} Array of inserted article records with IDs
 * @throws {Error} If database operation fails
 *
 * @example
 * const articles = await insertArticles(supabase, newspaperId, [
 *   {
 *     title: 'Election Results',
 *     section: 'Politics',
 *     page_number: 1,
 *     content_preview: 'Results show...',
 *     quality_score: 0.95
 *   },
 *   {
 *     title: 'Cricket Championship',
 *     section: 'Sports',
 *     page_number: 8,
 *     quality_score: 0.87
 *   }
 * ]);
 */
async function insertArticles(supabase, newspaperId, articles) {
  const articlesWithNewspaperId = articles.map(article => ({
    newspaper_id: newspaperId,
    ...article
  }));

  const { data: inserted, error } = await supabase
    .from('articles')
    .insert(articlesWithNewspaperId)
    .select();

  if (error) throw error;
  return inserted;
}

/**
 * Insert a single article
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} newspaperId - Parent newspaper UUID
 * @param {Object} article - Article data (see insertArticles for schema)
 *
 * @returns {Promise<Object>} Inserted article record
 * @throws {Error} If database operation fails
 */
async function insertArticle(supabase, newspaperId, article) {
  const { data: inserted, error } = await supabase
    .from('articles')
    .insert([{
      newspaper_id: newspaperId,
      ...article
    }])
    .select()
    .single();

  if (error) throw error;
  return inserted;
}

/**
 * Get all articles for a specific newspaper
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} newspaperId - Newspaper UUID
 * @param {Object} [options] - Query options
 * @param {string} [options.section] - Filter by section
 * @param {string} [options.orderBy] - Order field (default: 'page_number')
 * @param {string} [options.order] - Sort direction: 'asc' or 'desc' (default: 'asc')
 *
 * @returns {Promise<Array>} Array of article records
 * @throws {Error} If database operation fails
 *
 * @example
 * const articles = await getArticlesByNewspaper(supabase, newspaperId, {
 *   section: 'Sports',
 *   orderBy: 'quality_score',
 *   order: 'desc'
 * });
 */
async function getArticlesByNewspaper(supabase, newspaperId, options = {}) {
  const { section, orderBy = 'page_number', order = 'asc' } = options;

  let query = supabase
    .from('articles')
    .select()
    .eq('newspaper_id', newspaperId);

  if (section) {
    query = query.eq('section', section);
  }

  const { data: articles, error } = await query
    .order(orderBy, { ascending: order === 'asc' });

  if (error) throw error;
  return articles;
}

/**
 * Get high-quality articles across newspapers (ranked by score)
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {number} [minQualityScore] - Minimum quality score threshold (default: 0.75)
 * @param {number} [limit] - Maximum number of articles to return (default: 50)
 *
 * @returns {Promise<Array>} Array of high-quality articles, sorted by quality descending
 * @throws {Error} If database operation fails
 */
async function getHighQualityArticles(supabase, minQualityScore = 0.75, limit = 50) {
  const { data: articles, error } = await supabase
    .from('articles')
    .select()
    .gte('quality_score', minQualityScore)
    .order('quality_score', { ascending: false })
    .limit(limit);

  if (error) throw error;
  return articles;
}

/**
 * Update article processing status and audio URL after TTS generation
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} articleId - Article UUID
 * @param {Object} updates - Fields to update
 * @param {string} [updates.processing_status] - New processing status
 * @param {string} [updates.audio_url] - Generated audio file URL
 * @param {number} [updates.quality_score] - Updated quality score
 *
 * @returns {Promise<Object>} Updated article record
 * @throws {Error} If database operation fails
 */
async function updateArticle(supabase, articleId, updates) {
  const { data: updated, error } = await supabase
    .from('articles')
    .update(updates)
    .eq('id', articleId)
    .select()
    .single();

  if (error) throw error;
  return updated;
}

// ============================================================================
// ARTICLE SEARCH, FILTER, & ANALYTICS OPERATIONS
// ============================================================================

/**
 * Search articles by title and content preview using full-text search
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} query - Search query string
 * @param {number} [limit] - Maximum number of results (default: 20, max: 100)
 * @param {number} [offset] - Pagination offset (default: 0)
 *
 * @returns {Promise<Object>} Response with success flag, data array, and optional error
 * @returns {boolean} result.success - Whether query succeeded
 * @returns {Array} result.data - Array of matching article records
 * @returns {string} [result.error] - Error message if operation failed
 *
 * @example
 * const result = await searchArticles(supabase, 'election 2026', 20, 0);
 * if (result.success) {
 *   console.log(`Found ${result.data.length} articles`);
 * }
 */
async function searchArticles(supabase, query, limit = 20, offset = 0) {
  try {
    // Validate and normalize parameters
    if (!query || typeof query !== 'string') {
      return { success: false, data: [], error: 'Query must be a non-empty string' };
    }

    const normalizedLimit = Math.min(Math.max(1, limit || 20), 100);
    const normalizedOffset = Math.max(0, offset || 0);
    const searchTerm = query.trim();

    // Use ILIKE for case-insensitive substring matching across title and content_preview
    const { data, error } = await supabase
      .from('articles')
      .select('id, title, content_preview, section, image_url, audio_url, quality_score, created_at, newspaper_id')
      .or(`title.ilike.%${searchTerm}%,content_preview.ilike.%${searchTerm}%`)
      .order('created_at', { ascending: false })
      .range(normalizedOffset, normalizedOffset + normalizedLimit - 1);

    if (error) {
      return { success: false, data: [], error: error.message };
    }

    return { success: true, data: data || [] };
  } catch (err) {
    return { success: false, data: [], error: err.message };
  }
}

/**
 * Filter articles by section with pagination
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} section - Section/category name to filter by
 * @param {number} [limit] - Maximum number of results (default: 20, max: 100)
 * @param {number} [offset] - Pagination offset (default: 0)
 *
 * @returns {Promise<Object>} Response with success flag, data array, and optional error
 * @returns {boolean} result.success - Whether query succeeded
 * @returns {Array} result.data - Array of articles in the section
 * @returns {string} [result.error] - Error message if operation failed
 *
 * @example
 * const result = await filterBySection(supabase, 'Sports', 20, 0);
 */
async function filterBySection(supabase, section, limit = 20, offset = 0) {
  try {
    if (!section || typeof section !== 'string') {
      return { success: false, data: [], error: 'Section must be a non-empty string' };
    }

    const normalizedLimit = Math.min(Math.max(1, limit || 20), 100);
    const normalizedOffset = Math.max(0, offset || 0);

    const { data, error } = await supabase
      .from('articles')
      .select('id, title, section, content_preview, image_url, audio_url, quality_score, page_number, created_at, newspaper_id')
      .eq('section', section)
      .order('created_at', { ascending: false })
      .range(normalizedOffset, normalizedOffset + normalizedLimit - 1);

    if (error) {
      return { success: false, data: [], error: error.message };
    }

    return { success: true, data: data || [] };
  } catch (err) {
    return { success: false, data: [], error: err.message };
  }
}

/**
 * Get all available sections with article counts
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 *
 * @returns {Promise<Object>} Response with success flag, data array, and optional error
 * @returns {boolean} result.success - Whether query succeeded
 * @returns {Array} result.data - Array of {section, count} objects
 * @returns {string} [result.error] - Error message if operation failed
 *
 * @example
 * const result = await getAvailableSections(supabase);
 * // Returns: { success: true, data: [
 * //   { section: 'Sports', count: 45 },
 * //   { section: 'Politics', count: 32 },
 * //   { section: 'Technology', count: 28 }
 * // ]}
 */
async function getAvailableSections(supabase) {
  try {
    const { data, error } = await supabase
      .from('articles')
      .select('section')
      .not('section', 'is', null);

    if (error) {
      return { success: false, data: [], error: error.message };
    }

    // Group by section and count
    const sectionCounts = {};
    if (data && Array.isArray(data)) {
      data.forEach(article => {
        if (article.section) {
          sectionCounts[article.section] = (sectionCounts[article.section] || 0) + 1;
        }
      });
    }

    // Convert to array and sort by count descending
    const sections = Object.entries(sectionCounts)
      .map(([section, count]) => ({ section, count }))
      .sort((a, b) => b.count - a.count);

    return { success: true, data: sections };
  } catch (err) {
    return { success: false, data: [], error: err.message };
  }
}

/**
 * Get articles sorted by quality score or creation date with pagination
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} [sortBy] - Sort field: 'quality_score' or 'created_at' (default: 'quality_score')
 * @param {number} [limit] - Maximum number of results (default: 20, max: 100)
 * @param {number} [offset] - Pagination offset (default: 0)
 *
 * @returns {Promise<Object>} Response with success flag, data array, and optional error
 * @returns {boolean} result.success - Whether query succeeded
 * @returns {Array} result.data - Array of sorted articles
 * @returns {string} [result.error] - Error message if operation failed
 *
 * @example
 * const result = await sortArticles(supabase, 'quality_score', 20, 0);
 */
async function sortArticles(supabase, sortBy = 'quality_score', limit = 20, offset = 0) {
  try {
    const validSortFields = ['quality_score', 'created_at'];
    const normalizedSortBy = validSortFields.includes(sortBy) ? sortBy : 'quality_score';
    const normalizedLimit = Math.min(Math.max(1, limit || 20), 100);
    const normalizedOffset = Math.max(0, offset || 0);

    const { data, error } = await supabase
      .from('articles')
      .select('id, title, section, content_preview, quality_score, image_url, audio_url, created_at, newspaper_id')
      .not('quality_score', 'is', null)
      .order(normalizedSortBy, { ascending: false })
      .range(normalizedOffset, normalizedOffset + normalizedLimit - 1);

    if (error) {
      return { success: false, data: [], error: error.message };
    }

    return { success: true, data: data || [] };
  } catch (err) {
    return { success: false, data: [], error: err.message };
  }
}

/**
 * Get all newspapers with article counts for each
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 *
 * @returns {Promise<Object>} Response with success flag, data array, and optional error
 * @returns {boolean} result.success - Whether query succeeded
 * @returns {Array} result.data - Array of newspaper objects with article_count
 * @returns {string} [result.error] - Error message if operation failed
 *
 * @example
 * const result = await getNewspapersWithCounts(supabase);
 * // Returns: { success: true, data: [
 * //   { id: 'uuid1', title: 'The Hindu', publication_date: '2026-05-23', article_count: 45 },
 * //   { id: 'uuid2', title: 'Times of India', publication_date: '2026-05-23', article_count: 38 }
 * // ]}
 */
async function getNewspapersWithCounts(supabase) {
  try {
    // Fetch all newspapers with count of related articles
    const { data: newspapers, error: newspapersError } = await supabase
      .from('newspapers')
      .select('id, title, publication_date, issue_number, language, storage_url, created_at')
      .order('publication_date', { ascending: false });

    if (newspapersError) {
      return { success: false, data: [], error: newspapersError.message };
    }

    if (!newspapers || newspapers.length === 0) {
      return { success: true, data: [] };
    }

    // Get article counts for all newspapers in one query
    const { data: articleCounts, error: countsError } = await supabase
      .from('articles')
      .select('newspaper_id');

    if (countsError) {
      return { success: false, data: [], error: countsError.message };
    }

    // Count articles by newspaper_id
    const countMap = {};
    if (articleCounts && Array.isArray(articleCounts)) {
      articleCounts.forEach(article => {
        if (article.newspaper_id) {
          countMap[article.newspaper_id] = (countMap[article.newspaper_id] || 0) + 1;
        }
      });
    }

    // Merge counts with newspaper data
    const newspapersWithCounts = newspapers.map(newspaper => ({
      ...newspaper,
      article_count: countMap[newspaper.id] || 0
    }));

    return { success: true, data: newspapersWithCounts };
  } catch (err) {
    return { success: false, data: [], error: err.message };
  }
}

// ============================================================================
// USER ARTICLES OPERATIONS
// ============================================================================

/**
 * Mark an article as read by a user
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} userId - User UUID (from auth.users)
 * @param {string} articleId - Article UUID
 *
 * @returns {Promise<Object>} User-article record with read_at timestamp
 * @throws {Error} If database operation fails
 *
 * @example
 * await markArticleAsRead(supabase, userId, articleId);
 * // Returns: { id, user_id, article_id, read_at: 2026-05-23T..., favorite: false, ... }
 */
async function markArticleAsRead(supabase, userId, articleId) {
  const { data: userArticle, error } = await supabase
    .from('user_articles')
    .upsert({
      user_id: userId,
      article_id: articleId,
      read_at: new Date().toISOString()
    }, { onConflict: 'user_id,article_id' })
    .select()
    .single();

  if (error) throw error;
  return userArticle;
}

/**
 * Toggle favorite status for an article
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} userId - User UUID
 * @param {string} articleId - Article UUID
 * @param {boolean} isFavorite - Favorite status (true/false)
 *
 * @returns {Promise<Object>} Updated user-article record
 * @throws {Error} If database operation fails
 */
async function toggleArticleFavorite(supabase, userId, articleId, isFavorite) {
  const { data: userArticle, error } = await supabase
    .from('user_articles')
    .upsert({
      user_id: userId,
      article_id: articleId,
      favorite: isFavorite
    }, { onConflict: 'user_id,article_id' })
    .select()
    .single();

  if (error) throw error;
  return userArticle;
}

/**
 * Add or update notes for an article
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} userId - User UUID
 * @param {string} articleId - Article UUID
 * @param {string} notes - User notes/annotations
 *
 * @returns {Promise<Object>} Updated user-article record
 * @throws {Error} If database operation fails
 */
async function updateArticleNotes(supabase, userId, articleId, notes) {
  const { data: userArticle, error } = await supabase
    .from('user_articles')
    .upsert({
      user_id: userId,
      article_id: articleId,
      notes
    }, { onConflict: 'user_id,article_id' })
    .select()
    .single();

  if (error) throw error;
  return userArticle;
}

/**
 * Get all articles read by a user
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} userId - User UUID
 * @param {Object} [options] - Query options
 * @param {boolean} [options.unreadOnly] - Only unread articles (default: false)
 * @param {boolean} [options.favoritesOnly] - Only favorite articles (default: false)
 * @param {number} [options.limit] - Maximum articles to return (default: 50)
 * @param {number} [options.offset] - Pagination offset (default: 0)
 *
 * @returns {Promise<Array>} Array of user-article records with joined article details
 * @throws {Error} If database operation fails
 */
async function getUserReadingHistory(supabase, userId, options = {}) {
  const { unreadOnly = false, favoritesOnly = false, limit = 50, offset = 0 } = options;

  let query = supabase
    .from('user_articles')
    .select(`
      id,
      user_id,
      article_id,
      read_at,
      favorite,
      notes,
      created_at,
      articles (
        id,
        title,
        section,
        image_url,
        audio_url,
        quality_score,
        newspaper_id
      )
    `)
    .eq('user_id', userId);

  if (unreadOnly) {
    query = query.is('read_at', null);
  }

  if (favoritesOnly) {
    query = query.eq('favorite', true);
  }

  const { data: userArticles, error } = await query
    .order('read_at', { ascending: false, nullsFirst: false })
    .range(offset, offset + limit - 1);

  if (error) throw error;
  return userArticles;
}

/**
 * Get user's favorite articles with full article details
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} userId - User UUID
 * @param {number} [limit] - Maximum articles to return (default: 50)
 * @param {number} [offset] - Pagination offset (default: 0)
 *
 * @returns {Promise<Array>} Array of favorite articles
 * @throws {Error} If database operation fails
 */
async function getUserFavoriteArticles(supabase, userId, limit = 50, offset = 0) {
  return getUserReadingHistory(supabase, userId, { favoritesOnly: true, limit, offset });
}

/**
 * Remove a user-article relationship (e.g., undo favorite or delete)
 *
 * @param {SupabaseClient} supabase - Initialized Supabase client
 * @param {string} userId - User UUID
 * @param {string} articleId - Article UUID
 *
 * @returns {Promise<void>}
 * @throws {Error} If database operation fails
 */
async function removeUserArticle(supabase, userId, articleId) {
  const { error } = await supabase
    .from('user_articles')
    .delete()
    .eq('user_id', userId)
    .eq('article_id', articleId);

  if (error) throw error;
}

// ============================================================================
// EXPORTS
// ============================================================================

export {
  // Newspaper operations
  insertNewspaper,
  getNewspaperById,
  getNewspapersByDateRange,

  // Article operations
  insertArticles,
  insertArticle,
  getArticlesByNewspaper,
  getHighQualityArticles,
  updateArticle,

  // Article search, filter, and analytics operations
  searchArticles,
  filterBySection,
  getAvailableSections,
  sortArticles,
  getNewspapersWithCounts,

  // User-article operations
  markArticleAsRead,
  toggleArticleFavorite,
  updateArticleNotes,
  getUserReadingHistory,
  getUserFavoriteArticles,
  removeUserArticle
};
