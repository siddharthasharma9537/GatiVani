# Database Integration Guide

Quick start for integrating the article storage schema into the GatiVani backend.

## Files Created

```
packages/core/src/database/
├── migrations/
│   └── 001_create_articles_tables.sql    (234 lines, full schema)
├── article-repository.js                  (15KB, 16 helper functions)
├── README.md                              (comprehensive documentation)
└── INTEGRATION.md                         (this file)
```

## Setup Checklist

### Step 1: Deploy Schema to Supabase

Option A: Using Supabase Dashboard
1. Go to your project → SQL Editor
2. Create new query
3. Copy entire contents of `migrations/001_create_articles_tables.sql`
4. Click "Run"
5. Verify tables are created in the "Tables" sidebar

Option B: Using Supabase CLI
```bash
# From project root
supabase migration new create_articles_tables
# Copy migration/001_create_articles_tables.sql contents into supabase/migrations/{timestamp}_create_articles_tables.sql
supabase migration up
```

### Step 2: Add Environment Variables

Add to `.env` or deployment config:

```bash
# Supabase credentials
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=eyJhbGc...  # Public anon key
SUPABASE_SERVICE_ROLE_KEY=...  # Service role (admin operations)

# Optional: for custom JWT token signing
SUPABASE_JWT_SECRET=your-jwt-secret
```

### Step 3: Install Dependencies

```bash
cd packages/core
npm install @supabase/supabase-js
```

### Step 4: Create Supabase Client Singleton

Create `src/lib/supabase.js`:

```javascript
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_ANON_KEY
);

module.exports = { supabase };
```

### Step 5: Use Repository in Your Routes

Example: Store processed articles after OCR

```javascript
// src/routes/articles.js
const express = require('express');
const { supabase } = require('../lib/supabase');
const repo = require('../database/article-repository');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

/**
 * POST /api/articles/store
 * Store newspaper and extracted articles
 */
router.post('/store', requireAuth, async (req, res) => {
  try {
    const { title, publication_date, issue_number, language, articles } = req.body;

    // Create newspaper record
    const newspaper = await repo.insertNewspaper(supabase, {
      title,
      publication_date, // "2026-05-23"
      issue_number,
      language: language || 'en'
    });

    // Batch insert all articles
    const stored = await repo.insertArticles(
      supabase,
      newspaper.id,
      articles.map(article => ({
        title: article.title,
        section: article.section,
        page_number: article.page_number,
        content_preview: article.preview,
        full_content: article.fullText,
        position_json: article.bbox, // {x, y, w, h}
        image_url: article.imageUrl,
        quality_score: article.confidence || 0.85,
        processing_status: 'processing' // TTS will update to 'completed'
      }))
    );

    res.json({
      success: true,
      newspaper: {
        id: newspaper.id,
        title: newspaper.title,
        articleCount: stored.length
      }
    });
  } catch (error) {
    console.error('Failed to store articles:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/articles/:newspaperId
 * Retrieve all articles from a newspaper
 */
router.get('/:newspaperId', async (req, res) => {
  try {
    const articles = await repo.getArticlesByNewspaper(
      supabase,
      req.params.newspaperId
    );
    res.json(articles);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
```

Wire into main app:

```javascript
// src/server.js
const articlesRouter = require('./routes/articles');
app.use('/api/articles', articlesRouter);
```

## Common Workflows

### Processing Pipeline

```javascript
// 1. User uploads newspaper
// 2. Extract articles via OCR/PDF
const articles = await ocrService.extractArticles(file);

// 3. Store in database
const newspaper = await repo.insertNewspaper(supabase, {
  title: 'The Times',
  publication_date: new Date().toISOString().split('T')[0],
  language: 'en'
});

const stored = await repo.insertArticles(supabase, newspaper.id, articles);

// 4. Generate TTS audio (async task)
for (const article of stored) {
  updateArticleAudio(article.id); // background job
}

// 5. User reads article
await repo.markArticleAsRead(supabase, userId, article.id);

// 6. User adds to favorites
await repo.toggleArticleFavorite(supabase, userId, article.id, true);
```

### Serving Articles to Frontend

```javascript
// Get newspaper with all articles
const newspaper = await repo.getNewspaperById(supabase, newspaperId);
const articles = await repo.getArticlesByNewspaper(supabase, newspaperId);

// Get user's reading history
const history = await repo.getUserReadingHistory(supabase, userId);

// Get recommendations (high-quality unread articles)
const recommendations = await repo.getHighQualityArticles(supabase, 0.85, 10);
```

### Updating After TTS Generation

```javascript
// After Supabase Edge Function generates audio
const audioUrl = 'https://audio-cdn.example.com/article-abc123.mp3';

await repo.updateArticle(supabase, articleId, {
  processing_status: 'completed',
  audio_url: audioUrl,
  quality_score: 0.93
});
```

## Authentication

The repository assumes Supabase client is initialized with proper JWT context. For different scenarios:

**Scenario 1: User actions (authenticated)**
```javascript
// Client has auth context automatically
const supabase = createClient(URL, KEY);
// auth.uid() is available in RLS policies
await repo.markArticleAsRead(supabase, userId, articleId);
```

**Scenario 2: Admin/backend operations (service role)**
```javascript
// Use service role key for admin bypass of RLS
const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);
await repo.insertArticles(supabaseAdmin, newspaperId, articles);
```

**Scenario 3: Set auth context manually**
```javascript
await supabase.auth.setSession({
  access_token: userToken,
  refresh_token: refreshToken
});
```

## Error Handling

All repository functions throw errors on database failures. Wrap in try-catch:

```javascript
try {
  const articles = await repo.getArticlesByNewspaper(supabase, newspaperId);
} catch (error) {
  if (error.code === 'PGRST116') {
    // Not found
    res.status(404).json({ error: 'Newspaper not found' });
  } else if (error.message.includes('violates row level security')) {
    // RLS denied access
    res.status(403).json({ error: 'Access denied' });
  } else {
    // Database error
    console.error('DB error:', error);
    res.status(500).json({ error: 'Database error' });
  }
}
```

## Testing

Example Jest test setup:

```javascript
// tests/article-repository.test.js
const { createClient } = require('@supabase/supabase-js');
const repo = require('../src/database/article-repository');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_ANON_KEY
);

describe('Article Repository', () => {
  let newspaperId;

  beforeAll(async () => {
    const newspaper = await repo.insertNewspaper(supabase, {
      title: 'Test Paper',
      publication_date: '2026-05-23',
      language: 'en'
    });
    newspaperId = newspaper.id;
  });

  afterAll(async () => {
    // Cleanup: delete newspaper (cascades to articles)
    // NOTE: Requires DELETE permission, might need service role
  });

  test('insertArticles should batch insert', async () => {
    const articles = await repo.insertArticles(supabase, newspaperId, [
      { title: 'Article 1', section: 'Sports', quality_score: 0.9 },
      { title: 'Article 2', section: 'Politics', quality_score: 0.85 }
    ]);

    expect(articles).toHaveLength(2);
    expect(articles[0].title).toBe('Article 1');
  });

  test('getArticlesByNewspaper should filter', async () => {
    const articles = await repo.getArticlesByNewspaper(
      supabase,
      newspaperId,
      { section: 'Sports' }
    );

    expect(articles.every(a => a.section === 'Sports')).toBe(true);
  });

  test('markArticleAsRead should update timestamp', async () => {
    const articleId = articles[0].id;
    const userId = 'test-user-id';

    const ua = await repo.markArticleAsRead(supabase, userId, articleId);

    expect(ua.read_at).toBeTruthy();
    expect(new Date(ua.read_at)).toBeInstanceOf(Date);
  });
});
```

## Troubleshooting

### Error: "SUPABASE_URL is required"
- Check `.env` file has `SUPABASE_URL` set
- Ensure environment variables are loaded before app starts

### Error: "Cannot read property 'select' of undefined"
- Supabase client not initialized
- Check `createClient()` call has correct URL and key

### Error: "row level security policy ... check expression was violated"
- Operation denied by RLS
- For user operations: ensure authenticated user context
- For admin: use `SUPABASE_SERVICE_ROLE_KEY`

### Slow queries on user_articles
- Check indexes exist (migration includes all needed indexes)
- Use `getUserReadingHistory()` with filters instead of unfiltered queries
- Consider pagination for large user libraries

## Next Steps

1. **Deploy migration** to Supabase (see Step 1)
2. **Add environment variables** (see Step 2)
3. **Create Supabase client singleton** (see Step 4)
4. **Wire repository into routes** (see Step 5)
5. **Update document processing** to call `insertArticles()`
6. **Add RLS tests** to verify access control
7. **Monitor performance** with Supabase analytics dashboard

## See Also

- [README.md](./README.md) — Full schema documentation
- [article-repository.js](./article-repository.js) — API reference with all function signatures
- [Supabase Docs](https://supabase.com/docs) — PostgreSQL, RLS, Auth
- [Supabase JS Client](https://supabase.com/docs/reference/javascript/introduction)
