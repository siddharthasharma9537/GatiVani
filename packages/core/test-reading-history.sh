#!/bin/bash

# Test script for Reading History & Favorites API
# Tests the article tracking endpoints with JWT authentication
#
# Prerequisites:
#   - Backend running on http://localhost:8788
#   - Supabase configured with SUPABASE_URL and SUPABASE_ANON_KEY
#   - Valid JWT token from Supabase auth
#
# Usage:
#   chmod +x test-reading-history.sh
#   ./test-reading-history.sh <JWT_TOKEN> <ARTICLE_ID>
#
# Example:
#   ./test-reading-history.sh "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." "550e8400-e29b-41d4-a716-446655440000"

set -e

API_BASE="http://localhost:8788"
JWT_TOKEN="${1:-}"
ARTICLE_ID="${2:-550e8400-e29b-41d4-a716-446655440000}"

if [ -z "$JWT_TOKEN" ]; then
  echo "Usage: $0 <JWT_TOKEN> [ARTICLE_ID]"
  echo ""
  echo "JWT_TOKEN: Supabase JWT token (from auth)"
  echo "ARTICLE_ID: Article UUID to test (default: 550e8400-e29b-41d4-a716-446655440000)"
  exit 1
fi

echo "=========================================="
echo "Reading History & Favorites API Tests"
echo "=========================================="
echo ""
echo "API Base: $API_BASE"
echo "JWT Token: ${JWT_TOKEN:0:20}..."
echo "Article ID: $ARTICLE_ID"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Test 1: Mark Article as Read
# ──────────────────────────────────────────────────────────────────────────────
echo "Test 1: Mark article as read"
echo "POST /api/articles/$ARTICLE_ID/mark-read"
echo ""

RESPONSE=$(curl -s -X POST "$API_BASE/api/articles/$ARTICLE_ID/mark-read" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "readAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }')

echo "Response:"
echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Test 2: Toggle Favorite
# ──────────────────────────────────────────────────────────────────────────────
echo "Test 2: Toggle favorite status"
echo "POST /api/articles/$ARTICLE_ID/toggle-favorite"
echo ""

RESPONSE=$(curl -s -X POST "$API_BASE/api/articles/$ARTICLE_ID/toggle-favorite" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "isFavorite": true
  }')

echo "Response:"
echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Test 3: Add Notes
# ──────────────────────────────────────────────────────────────────────────────
echo "Test 3: Add article notes"
echo "POST /api/articles/$ARTICLE_ID/notes"
echo ""

RESPONSE=$(curl -s -X POST "$API_BASE/api/articles/$ARTICLE_ID/notes" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "notes": "Important article - contains key information about election results"
  }')

echo "Response:"
echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Test 4: Get Reading History
# ──────────────────────────────────────────────────────────────────────────────
echo "Test 4: Get reading history"
echo "GET /api/user/reading-history?limit=10&offset=0"
echo ""

RESPONSE=$(curl -s -X GET "$API_BASE/api/user/reading-history?limit=10&offset=0" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json")

echo "Response:"
echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Test 5: Get Favorites
# ──────────────────────────────────────────────────────────────────────────────
echo "Test 5: Get favorite articles"
echo "GET /api/user/favorites?limit=10&offset=0"
echo ""

RESPONSE=$(curl -s -X GET "$API_BASE/api/user/favorites?limit=10&offset=0" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json")

echo "Response:"
echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Test 6: Unauthorized Request (missing token)
# ──────────────────────────────────────────────────────────────────────────────
echo "Test 6: Unauthorized request (missing token)"
echo "GET /api/user/reading-history"
echo ""

RESPONSE=$(curl -s -X GET "$API_BASE/api/user/reading-history" \
  -H "Content-Type: application/json")

echo "Response:"
echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
echo ""

echo "=========================================="
echo "Tests complete!"
echo "=========================================="
