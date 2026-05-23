#!/usr/bin/env node

/**
 * Test Script for Articles API Endpoints
 *
 * Validates that all 5 articles API endpoints respond with valid JSON:
 * 1. GET /api/articles/search?q=test
 * 2. GET /api/articles/filter?section=News
 * 3. GET /api/articles/sort?by=quality
 * 4. GET /api/articles/sections
 * 5. GET /api/newspapers
 *
 * Usage: node test-articles-api.js [baseUrl] [jwtToken]
 * Example: node test-articles-api.js http://localhost:8788
 */

import fetch from 'node:fetch';

const API_BASE_URL = process.argv[2] || 'http://localhost:8788';
const JWT_TOKEN = process.argv[3] || null;

const endpoints = [
  {
    name: 'Search Articles',
    url: `${API_BASE_URL}/api/articles/search?q=test`,
    requiresAuth: false
  },
  {
    name: 'Filter by Section',
    url: `${API_BASE_URL}/api/articles/filter?section=News`,
    requiresAuth: false
  },
  {
    name: 'Sort Articles',
    url: `${API_BASE_URL}/api/articles/sort?by=quality`,
    requiresAuth: false
  },
  {
    name: 'Get Sections',
    url: `${API_BASE_URL}/api/articles/sections`,
    requiresAuth: false
  },
  {
    name: 'Get Newspapers',
    url: `${API_BASE_URL}/api/newspapers`,
    requiresAuth: false
  }
];

async function testEndpoint(endpoint) {
  const headers = {
    'Content-Type': 'application/json'
  };

  if (endpoint.requiresAuth && JWT_TOKEN) {
    headers.Authorization = `Bearer ${JWT_TOKEN}`;
  }

  try {
    console.log(`\nTesting: ${endpoint.name}`);
    console.log(`URL: ${endpoint.url}`);

    const response = await fetch(endpoint.url, { headers });
    const contentType = response.headers.get('content-type');

    if (!contentType || !contentType.includes('application/json')) {
      console.error(`  FAIL: Invalid content type. Expected application/json, got ${contentType}`);
      return false;
    }

    const data = await response.json();

    if (response.ok) {
      console.log(`  PASS: Status ${response.status}`);
      console.log(`  Response keys: ${Object.keys(data).join(', ')}`);
      if (Array.isArray(data)) {
        console.log(`  Array length: ${data.length}`);
      } else if (data.articles && Array.isArray(data.articles)) {
        console.log(`  Articles: ${data.articles.length}`);
      }
      return true;
    } else {
      console.error(`  Status ${response.status}: ${data.error || data.message}`);
      return false;
    }
  } catch (error) {
    console.error(`  ERROR: ${error.message}`);
    return false;
  }
}

async function runTests() {
  console.log('========================================');
  console.log('Articles API Endpoint Validation');
  console.log('========================================');
  console.log(`Base URL: ${API_BASE_URL}`);
  console.log(`JWT Token: ${JWT_TOKEN ? 'Provided' : 'Not provided'}`);
  console.log('');

  const results = [];
  for (const endpoint of endpoints) {
    const passed = await testEndpoint(endpoint);
    results.push({ name: endpoint.name, passed });
  }

  console.log('\n========================================');
  console.log('Summary');
  console.log('========================================');

  const passed = results.filter(r => r.passed).length;
  const total = results.length;

  results.forEach(r => {
    const status = r.passed ? '✓' : '✗';
    console.log(`${status} ${r.name}`);
  });

  console.log(`\nResult: ${passed}/${total} endpoints passed`);
  console.log('========================================\n');

  process.exit(passed === total ? 0 : 1);
}

runTests().catch(error => {
  console.error('Test failed:', error);
  process.exit(1);
});
