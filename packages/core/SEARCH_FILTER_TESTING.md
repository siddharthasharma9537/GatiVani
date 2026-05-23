# Article Search and Filtering - Testing Guide

This document provides comprehensive instructions for testing the search, filtering, and sorting functionality of the GatiVani article system.

## Backend API Endpoints

All endpoints are available at `http://localhost:8788/api/articles/` (or your configured server port).

### 1. Search Articles

**Endpoint:** `GET /api/articles/search`

**Query Parameters:**
- `q` (required): Search keyword/phrase
- `limit` (optional): Results per page, default 20, max 100
- `offset` (optional): Pagination offset, default 0

**Example Requests:**

```bash
# Search for "cricket"
curl "http://localhost:8788/api/articles/search?q=cricket&limit=20&offset=0"

# Search for "election" with pagination
curl "http://localhost:8788/api/articles/search?q=election&limit=10&offset=20"

# Search for "market" with small result set
curl "http://localhost:8788/api/articles/search?q=market&limit=5"
```

**Expected Response:**
```json
{
  "articles": [
    {
      "id": "uuid",
      "title": "Cricket Championship Results",
      "content_preview": "The cricket championship concluded yesterday...",
      "section": "Sports",
      "image_url": "https://...",
      "audio_url": "https://...",
      "quality_score": 0.95,
      "page_number": 1,
      "created_at": "2026-05-23T10:00:00Z",
      "newspapers": {
        "id": "uuid",
        "title": "The Hindu",
        "publication_date": "2026-05-23"
      }
    }
  ],
  "total": 150,
  "limit": 20,
  "offset": 0,
  "query": "cricket"
}
```

### 2. Filter by Section

**Endpoint:** `GET /api/articles/filter`

**Query Parameters:**
- `section` (required): Section name (e.g., "Politics", "Sports", "Business")
- `limit` (optional): Results per page, default 20, max 100
- `offset` (optional): Pagination offset, default 0

**Example Requests:**

```bash
# Filter by Sports section
curl "http://localhost:8788/api/articles/filter?section=Sports&limit=20"

# Filter by Politics with pagination
curl "http://localhost:8788/api/articles/filter?section=Politics&limit=10&offset=30"

# Filter by Business
curl "http://localhost:8788/api/articles/filter?section=Business"
```

**Expected Response:**
```json
{
  "articles": [
    {
      "id": "uuid",
      "title": "India vs Australia Cricket Match",
      "content_preview": "India defeated Australia in a thrilling match...",
      "section": "Sports",
      "image_url": "https://...",
      "audio_url": "https://...",
      "quality_score": 0.87,
      "page_number": 8,
      "created_at": "2026-05-23T09:30:00Z",
      "newspapers": {
        "id": "uuid",
        "title": "Times of India",
        "publication_date": "2026-05-23"
      }
    }
  ],
  "total": 78,
  "section": "Sports",
  "limit": 20,
  "offset": 0
}
```

### 3. Sort Articles

**Endpoint:** `GET /api/articles/sort`

**Query Parameters:**
- `by` (optional): Sort criteria - 'quality' (default) or 'date'
- `limit` (optional): Results per page, default 20, max 100
- `offset` (optional): Pagination offset, default 0

**Example Requests:**

```bash
# Sort by quality score (highest first)
curl "http://localhost:8788/api/articles/sort?by=quality&limit=20"

# Sort by publication date (newest first)
curl "http://localhost:8788/api/articles/sort?by=date&limit=20"

# Sort by date with pagination
curl "http://localhost:8788/api/articles/sort?by=date&limit=10&offset=40"

# Default sort (by date)
curl "http://localhost:8788/api/articles/sort"
```

**Expected Response:**
```json
{
  "articles": [
    {
      "id": "uuid",
      "title": "High Quality Article",
      "content_preview": "This is a comprehensive article with excellent content...",
      "section": "News",
      "image_url": "https://...",
      "audio_url": "https://...",
      "quality_score": 0.98,
      "page_number": 1,
      "created_at": "2026-05-23T08:00:00Z",
      "newspapers": {
        "id": "uuid",
        "title": "The Hindu",
        "publication_date": "2026-05-23"
      }
    }
  ],
  "total": 500,
  "sortBy": "quality",
  "limit": 20,
  "offset": 0
}
```

### 4. Get Available Sections

**Endpoint:** `GET /api/articles/sections`

**Query Parameters:** None

**Example Request:**

```bash
# Get all available sections
curl "http://localhost:8788/api/articles/sections"
```

**Expected Response:**
```json
[
  {
    "section": "Politics",
    "count": 45
  },
  {
    "section": "Sports",
    "count": 78
  },
  {
    "section": "Business",
    "count": 32
  },
  {
    "section": "Health",
    "count": 25
  },
  {
    "section": "Technology",
    "count": 38
  },
  {
    "section": "Entertainment",
    "count": 42
  }
]
```

### 5. Get Newspapers with Counts

**Endpoint:** `GET /api/newspapers`

**Query Parameters:** None

**Example Request:**

```bash
# Get all newspapers with article counts
curl "http://localhost:8788/api/newspapers"
```

**Expected Response:**
```json
[
  {
    "id": "uuid",
    "title": "The Hindu",
    "publication_date": "2026-05-23",
    "language": "en",
    "article_count": 45
  },
  {
    "id": "uuid",
    "title": "Times of India",
    "publication_date": "2026-05-23",
    "language": "en",
    "article_count": 67
  },
  {
    "id": "uuid",
    "title": "The Hindu",
    "publication_date": "2026-05-22",
    "language": "en",
    "article_count": 52
  }
]
```

## Testing Checklist

### Search Functionality

- [ ] **Basic Search**: Search for "cricket" returns relevant articles
- [ ] **Case Insensitivity**: Search for "CRICKET", "Cricket", "cricket" returns same results
- [ ] **Partial Matching**: Search for "crick" finds articles containing "cricket"
- [ ] **Multiple Words**: Search for "world cup" finds articles with both terms
- [ ] **Empty Query**: Searching with empty `q` returns 400 error
- [ ] **Pagination**: First page (offset=0) and second page (offset=20) return different results
- [ ] **Result Limit**: Setting `limit=5` returns max 5 articles
- [ ] **Total Count**: `total` field reflects actual number of matching articles
- [ ] **Performance**: Search completes in under 500ms

### Filtering Functionality

- [ ] **Section Filter**: Filter by "Sports" returns only sports articles
- [ ] **Multiple Sections**: Filter works for Politics, Business, Health, Technology
- [ ] **Empty Section**: Missing `section` parameter returns 400 error
- [ ] **Case Sensitivity**: Section names are case-sensitive
- [ ] **Pagination**: Multiple pages of filtered results work correctly
- [ ] **Result Count**: Filtered result count matches expected count
- [ ] **Performance**: Filter operation completes in under 500ms

### Sorting Functionality

- [ ] **Sort by Quality**: Articles ordered by quality_score DESC
- [ ] **Sort by Date**: Articles ordered by created_at DESC (newest first)
- [ ] **Default Sort**: Omitting `by` parameter sorts by date
- [ ] **Invalid Sort**: Using invalid `by` value returns 400 error
- [ ] **Pagination**: Sorted results paginate correctly
- [ ] **Top Results**: First article in quality sort has highest quality_score
- [ ] **Performance**: Sort operation completes in under 500ms

### Section Statistics

- [ ] **All Sections Listed**: Returns list of all unique sections
- [ ] **Accurate Counts**: Article count matches actual number for each section
- [ ] **Performance**: Sections endpoint responds in under 200ms

### Newspaper Listing

- [ ] **All Newspapers Listed**: Returns all newspaper editions
- [ ] **Article Count Accurate**: article_count matches articles in database
- [ ] **Sorted by Date**: Newspapers ordered by publication_date DESC
- [ ] **Language Included**: Language field present for each newspaper
- [ ] **Performance**: Responds in under 300ms

## Performance Testing

### Setup Test Data

Create 100+ test articles across multiple sections:

```bash
# Example: Create articles via backend
# (This assumes you have a seeding script or manual insert)

# Articles should include:
# - 45 Politics articles (quality scores 0.70-0.99)
# - 78 Sports articles (quality scores 0.75-0.95)
# - 32 Business articles (quality scores 0.80-0.98)
# - 25 Health articles (quality scores 0.72-0.92)
# - 20+ with various publication dates
```

### Performance Benchmarks

Run the following tests and measure response times:

```bash
# Test 1: Search Performance (should complete in <500ms)
time curl "http://localhost:8788/api/articles/search?q=cricket&limit=20"

# Test 2: Filter Performance (should complete in <500ms)
time curl "http://localhost:8788/api/articles/filter?section=Sports"

# Test 3: Sort by Quality (should complete in <500ms)
time curl "http://localhost:8788/api/articles/sort?by=quality&limit=20"

# Test 4: Sort by Date (should complete in <500ms)
time curl "http://localhost:8788/api/articles/sort?by=date&limit=20"

# Test 5: Pagination Deep Offset (offset=1000, should still be <500ms)
time curl "http://localhost:8788/api/articles/search?q=cricket&offset=1000&limit=20"
```

### Load Testing

Test with concurrent requests:

```bash
# Using Apache Bench (install with: apt-get install apache2-utils)

# 100 concurrent requests to search endpoint
ab -n 1000 -c 100 'http://localhost:8788/api/articles/search?q=cricket&limit=20'

# 100 concurrent requests to filter endpoint
ab -n 1000 -c 100 'http://localhost:8788/api/articles/filter?section=Sports'

# 50 concurrent requests to sort endpoint
ab -n 500 -c 50 'http://localhost:8788/api/articles/sort?by=quality'
```

Expected Results:
- Search: <500ms response time, <2% failure rate
- Filter: <400ms response time, <1% failure rate
- Sort: <500ms response time, <1% failure rate

## Mobile UI Testing

### Search Screen

- [ ] Search bar appears and accepts input
- [ ] Results load and display as user types (with debounce)
- [ ] Clear button removes search text
- [ ] Results show article title, preview, source, category
- [ ] Play button navigates to PlayerScreen
- [ ] "Load More" button appears when more results exist
- [ ] Loading spinner shows during search
- [ ] Error state displays when search fails
- [ ] Responsive on mobile (375px width)

### Filter Screen

- [ ] Section tabs display all available categories
- [ ] Article count shows for each section
- [ ] Clicking section loads articles in that section
- [ ] Articles display with title, preview, source
- [ ] "Load More" pagination works
- [ ] Section selection is visually highlighted
- [ ] Empty state shows when section has no articles
- [ ] Error state displays when loading fails
- [ ] Responsive layout on mobile

### Sort Screen

- [ ] Sort options display (Quality, Date)
- [ ] Selection radio buttons work correctly
- [ ] Articles load based on selected sort
- [ ] Articles ordered correctly (quality DESC or date DESC)
- [ ] Time display shows "2h ago", "5d ago" format
- [ ] Pagination works for sorted results
- [ ] Error state displays and retry works
- [ ] Responsive on mobile

### Integration with Article List

- [ ] Search button visible in article list header
- [ ] Filter button visible in article list header
- [ ] Sort button visible in article list header
- [ ] Navigation to search/filter/sort screens works
- [ ] Back button returns to article list
- [ ] No layout shifts when buttons visible

## Database Query Performance

### Verify Indexes

```sql
-- Check if search index exists
SELECT * FROM pg_indexes 
WHERE tablename = 'articles' 
AND indexname LIKE '%title%' OR indexname LIKE '%content%';

-- Check if section filter index exists
SELECT * FROM pg_indexes 
WHERE tablename = 'articles' 
AND indexname LIKE '%section%';

-- Check if quality sort index exists
SELECT * FROM pg_indexes 
WHERE tablename = 'articles' 
AND indexname LIKE '%quality%';

-- Verify indexes are being used (EXPLAIN plan)
EXPLAIN (ANALYZE) 
SELECT * FROM articles 
WHERE title ILIKE '%cricket%' 
LIMIT 20;

EXPLAIN (ANALYZE) 
SELECT * FROM articles 
WHERE section = 'Sports' 
LIMIT 20;

EXPLAIN (ANALYZE) 
SELECT * FROM articles 
ORDER BY quality_score DESC 
LIMIT 20;
```

## Troubleshooting

### Search Returns No Results

1. Check if articles are in the database: `SELECT COUNT(*) FROM articles;`
2. Verify the search keyword exists in title/content_preview
3. Check for encoding issues if using special characters
4. Review server logs for SQL errors

### Filter Returns Wrong Count

1. Verify section names in database: `SELECT DISTINCT section FROM articles;`
2. Check if section filter index is being used: `EXPLAIN SELECT...`
3. Ensure section column is populated correctly

### Performance Issues (>500ms)

1. Check database indexes: `SELECT * FROM pg_indexes WHERE tablename='articles';`
2. Analyze query execution plan: `EXPLAIN (ANALYZE) SELECT...`
3. Review slow query logs
4. Consider adding query caching for frequently accessed sections

### Mobile UI Issues

1. Check network requests in browser DevTools
2. Verify mock data is being returned if API not connected
3. Test on actual device for performance
4. Check for layout issues on different screen sizes

## Success Criteria

The search and filtering implementation is successful when:

1. **Functionality**
   - All 5 endpoints return correct data
   - Search returns relevant results
   - Filtering works for all sections
   - Sorting produces correct order
   - Pagination works correctly

2. **Performance**
   - All endpoints respond in <500ms with 100+ articles
   - Load tests show <2% failure rate at 100 concurrent requests
   - Database indexes are used for all search/filter/sort queries

3. **Mobile UI**
   - All three screens (search, filter, sort) are functional
   - Navigation works smoothly
   - Results display correctly on mobile
   - Responsive design works on 375px+ width screens

4. **Error Handling**
   - Missing required parameters return 400 errors
   - Invalid parameter values return appropriate errors
   - Network errors are handled gracefully
   - Database errors don't crash the app

5. **Data Quality**
   - Search accuracy > 95% (relevant results in top 5)
   - Filter accuracy 100% (all returned articles match section)
   - Sort accuracy 100% (articles in correct order)
   - No duplicate articles in results

## Integration with Backend

The search/filter endpoints are integrated into the Express.js server:

**Location:** `/packages/core/src/routes/articles.js`

**Server Registration:**
```javascript
// In server.js
app.use("/api/articles", articlesRouter);
```

**Required Environment Variables:**
- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_ANON_KEY` - Supabase anonymous key

## References

- Article Repository: `/packages/core/src/database/article-repository.js`
- API Routes: `/packages/core/src/routes/articles.js`
- Mobile Screens: `/packages/app/lib/screens/search_screen.dart`
- Mobile Screens: `/packages/app/lib/screens/filter_screen.dart`
- Mobile Screens: `/packages/app/lib/screens/sort_screen.dart`
