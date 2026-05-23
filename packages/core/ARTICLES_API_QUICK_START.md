# Articles API - Quick Start Guide

## Setup Status: COMPLETE ✓

All Supabase credentials and API endpoints have been configured and are ready for testing.

## Starting the Backend Server

### Prerequisites
- Node.js 18+ installed
- Supabase credentials configured in `.env` (already done)

### Start the Server

```bash
cd /Users/siddharthapothulapati/Workspace/gativani/packages/core

# Production mode
npm start

# Development mode with auto-reload
npm run dev
```

The server will start on port **8788** and output:
```
[voxnews-node-core] listening on port 8788
```

## Testing All 5 Endpoints

Once the server is running, test with the provided test script:

```bash
# Test all endpoints
node test-articles-api.js

# Test with custom base URL
node test-articles-api.js http://localhost:8788

# Test with JWT token (if needed for auth endpoints)
node test-articles-api.js http://localhost:8788 "your-jwt-token"
```

## Manual Testing with curl

### 1. Search Articles
```bash
curl "http://localhost:8788/api/articles/search?q=test&limit=10"
```
Expected response: Articles matching "test" in title or content

### 2. Filter by Section
```bash
curl "http://localhost:8788/api/articles/filter?section=News&limit=10"
```
Expected response: Articles in the "News" section

### 3. Sort Articles
```bash
curl "http://localhost:8788/api/articles/sort?by=quality&limit=10"
curl "http://localhost:8788/api/articles/sort?by=date&limit=10"
```
Expected response: Articles sorted by quality score or creation date

### 4. Get Sections
```bash
curl "http://localhost:8788/api/articles/sections"
```
Expected response: List of unique sections with article counts

### 5. Get Newspapers
```bash
curl "http://localhost:8788/api/newspapers"
```
Expected response: List of newspapers with article counts

## Example Responses

### Search Response
```json
{
  "articles": [
    {
      "id": "uuid",
      "title": "Article Title",
      "content_preview": "...",
      "section": "News",
      "quality_score": 0.95,
      "image_url": "https://...",
      "audio_url": "https://...",
      "newspaper_id": "uuid",
      "created_at": "2026-05-23T12:00:00Z"
    }
  ],
  "query": "test",
  "limit": 10,
  "offset": 0,
  "total": 5
}
```

### Sections Response
```json
[
  { "section": "Politics", "count": 45 },
  { "section": "Sports", "count": 78 },
  { "section": "Business", "count": 32 },
  { "section": "Technology", "count": 28 }
]
```

### Newspapers Response
```json
[
  {
    "id": "uuid-1",
    "title": "The Hindu",
    "publication_date": "2026-05-23",
    "language": "en",
    "article_count": 45
  },
  {
    "id": "uuid-2",
    "title": "Times of India",
    "publication_date": "2026-05-23",
    "language": "en",
    "article_count": 67
  }
]
```

## Error Responses

### Missing Required Parameter
```json
{
  "error": "invalid_request",
  "message": "Search query 'q' is required"
}
```
Status: 400 Bad Request

### Database Not Configured
```json
{
  "error": "service_unavailable",
  "message": "Supabase not configured"
}
```
Status: 503 Service Unavailable

### Database Error
```json
{
  "error": "search_failed",
  "message": "Error message from database"
}
```
Status: 500 Internal Server Error

## API Endpoints Reference

| Endpoint | Method | Parameters | Purpose |
|----------|--------|------------|---------|
| `/api/articles/search` | GET | q (required), limit, offset | Search articles by keyword |
| `/api/articles/filter` | GET | section (required), limit, offset | Filter articles by section |
| `/api/articles/sort` | GET | by (quality\|date), limit, offset | Sort articles |
| `/api/articles/sections` | GET | none | Get available sections |
| `/api/newspapers` | GET | none | Get all newspapers |

## Parameter Validation

All endpoints support pagination:
- `limit`: Max 100, default 20, min 1
- `offset`: Default 0, min 0

## Health Check

Verify the server is running:
```bash
curl "http://localhost:8788/health"
# or
curl "http://localhost:8788/api/health"
```

Response:
```json
{
  "ok": true,
  "service": "voxnews-node-core",
  "env": "production",
  "trustClientTierHeaders": false
}
```

## Troubleshooting

### Port Already in Use
If port 8788 is already in use, change it in `.env`:
```env
PORT=8789
```

### Supabase Connection Error
Verify credentials in `.env`:
```env
SUPABASE_URL=https://jjoxowdvzmlchtfarpbs.supabase.co
SUPABASE_ANON_KEY=sb_publishable_fNZOLe19iitMJpPnBngXmA_nsIIp30s
```

### No Data Returned
The API returns empty arrays if no articles match the query:
- No articles in the database yet
- Section name doesn't exist
- Quality score filter returns nothing

## Files Modified

1. **`.env`** - Added SUPABASE_URL and SUPABASE_ANON_KEY
2. **`src/server.js`** - Uncommented articlesRouter import and registration
3. **`src/routes/articles.js`** - Fixed function signatures and response handling
4. **`src/database/article-repository.js`** - Already had all functions implemented

## Next Steps

1. Populate the Supabase database with newspapers and articles
2. Run the test script to verify all endpoints work
3. Integrate with the Flutter frontend app
4. Add authentication with JWT tokens if needed

---

For detailed documentation, see: `SETUP_VALIDATION.md`
