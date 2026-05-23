# GatiVani Node.js Backend - Deployment Guide

## Overview
This guide covers the deployment of the GatiVani Node.js backend to Razorhost cPanel with full Sarvam AI integration (OCR + TTS).

## Architecture Changes

### Before (Removed)
- ❌ Gemini Vision for OCR (expensive)
- ❌ Gemini for content generation
- ❌ Multiple API dependencies

### After (Current)
- ✅ **Sarvam OCR** for document text extraction (Indian language optimized)
- ✅ **Sarvam TTS** for Telugu text-to-speech (Primary provider)
- ✅ **Azure TTS** as fallback provider
- ✅ Significantly reduced costs
- ✅ Better support for Indian languages

## Tech Stack

### Languages
- **Node.js v22.22** (verified on server)
- **JavaScript (ES6 modules)**

### Key Dependencies
- `express` - HTTP server framework
- `multer` - File upload handling
- `sarvamai` - Sarvam AI SDK (OCR + TTS)
- `unzipper` - ZIP file extraction
- `cors` - Cross-origin requests
- `helmet` - Security headers

### Service Integrations
1. **Sarvam AI** - OCR + TTS
2. **Azure Cognitive Services** - Fallback TTS
3. **Supabase** - Database (optional, disabled in current build)

## Deployment Steps

### 1. Prerequisites
- Razorhost cPanel account with SSH access
- Node.js v22+ installed on server
- npm installed and working
- Environment variables configured

### 2. SSH Access & File Upload

```bash
# Connect to Razorhost via SSH
ssh username@your-razorhost-domain.com

# Navigate to public_html or appropriate directory
cd ~/public_html  # or your preferred deployment directory

# Clone repository (if not already present)
git clone https://github.com/yourusername/gativani.git
cd gativani/packages/core
```

### 3. Environment Configuration

Create or update `.env` file with the following variables:

```bash
# Node Environment
NODE_ENV=production
PORT=8788

# Sarvam AI Configuration
SARVAM_API_KEY=sk_sdq8hvkp_emPfj2uc78TQZQnDiAKJCe4x

# Azure TTS Configuration (Fallback)
AZURE_TTS_KEY=your_azure_key_here
AZURE_TTS_REGION=centralindia

# TTS Provider Settings
TTS_PROVIDER=sarvam
ENABLE_TTS_FALLBACK=true

# Public Origin (for serving uploaded files)
PUBLIC_ORIGIN=http://your-razorhost-domain.com:8788

# Trust Client Headers (for subscription tier detection)
TRUST_CLIENT_TIER_HEADERS=true

# Node Environment
NODE_ENV=production
```

### 4. Install Dependencies

```bash
cd /path/to/gativani/packages/core

# Install npm packages
npm install

# Verify installation
npm list | grep "sarvamai\|unzipper" | head -10
```

### 5. Start the Server

#### Option A: Direct Node.js (Testing)
```bash
node src/server.js
```

#### Option B: Using npm (Recommended)
```bash
npm start
```

#### Option C: Using PM2 (Production Recommended)
```bash
# Install PM2 globally (if not already installed)
npm install -g pm2

# Start the application
pm2 start src/server.js --name voxnews-node-core

# Set to restart on reboot
pm2 startup
pm2 save
```

### 6. Verify Deployment

```bash
# Test health endpoint
curl http://localhost:8788/health

# Test root endpoint
curl http://localhost:8788/

# Expected response:
# {
#   "ok": true,
#   "service": "voxnews-node-core",
#   "env": "production",
#   "trustClientTierHeaders": true
# }
```

## API Endpoints

### Health Check
```
GET /health
GET /api/health
```

### Document Processing (Full Pipeline)
```
POST /api/documents/process
Headers: X-Subscription-Tier: free|standard|premium
Content-Type: multipart/form-data
Body: { document: <file> }

Response:
{
  ok: true,
  newspaper: { id, title, date, storageUrl },
  articles: [{ id, title, section, preview, audioUrl, qualityScore, status }],
  models: { ocr: "sarvam-ocr", tts: "sarvam-tts" },
  summary: { totalArticles, processedArticles, failedArticles, processingTime },
  subscription: { tier, active },
  limits: { maxPages, totalPages, processedPages, truncated }
}
```

### Text-to-Speech (Direct)
```
POST /api/documents/synthesize
Headers: X-Subscription-Tier: free|standard|premium
Content-Type: application/json

Body:
{
  "text": "నమస్కారం...",
  "language": "te-IN"
}

Response:
{
  ok: true,
  audioUrl: "data:audio/mpeg;base64,..{base64 audio data}...",
  provider: "sarvam"
}
```

## File Structure

```
packages/core/
├── src/
│   ├── config/
│   │   └── env.js                        # Environment configuration
│   ├── middleware/
│   │   ├── auth.js                       # Authentication middleware
│   │   └── subscription.js               # Subscription tier validation
│   ├── routes/
│   │   └── documents.js                  # Document processing routes
│   ├── services/
│   │   ├── stage1-preprocessing.js       # OCR text extraction
│   │   ├── stage2-datacleaning.js        # Text cleaning
│   │   ├── stage3-postprocessing.js      # Quality verification
│   │   ├── sarvam-vision-service.js      # Sarvam OCR implementation
│   │   ├── sarvam-tts-service.js         # Sarvam TTS with Telugu voices
│   │   ├── tts-fallback-service.js       # TTS provider fallback logic
│   │   └── article-segmentation-service.js # Article detection (simplified)
│   ├── lib/
│   │   └── subscription-tiers.js         # Subscription tier limits
│   └── server.js                         # Express server setup
├── .env                                  # Environment variables
├── .env.example                          # Example environment file
├── package.json                          # npm dependencies
└── node_modules/                         # npm packages
```

## Sarvam OCR Configuration

### Supported Languages
- Telugu (te) - 48000 Hz sample rate
- Hindi (hi) - 22050 Hz sample rate
- English (en) - 22050 Hz sample rate

### Available Telugu Voices (for TTS)
1. **Shubh** (Male) - Default, natural male voice
2. **Shreya** (Female) - Natural female voice
3. **Anushka** (Female) - Professional female voice
4. **Vidya** (Female) - Warm female voice
5. **Manisha** (Female) - Clear female voice
6. **Arya** (Male) - Calm male voice

Example voice selection:
```javascript
// Default voice (automatically uses "shubh" for Telugu)
generateAudioWithFallback(text, "te");

// Specific voice
generateAudioWithFallback(text, "te", "shreya");
```

## Troubleshooting

### Port Already in Use
```bash
# Find process using port 8788
lsof -i :8788

# Kill the process
kill -9 <PID>
```

### SARVAM_API_KEY Not Configured
```bash
# Check .env file exists and contains the key
cat .env | grep SARVAM_API_KEY

# Verify it's being loaded
curl http://localhost:8788/health
```

### ZIP Extraction Errors
The Sarvam OCR returns results as ZIP files. Ensure `unzipper` package is installed:
```bash
npm install unzipper
```

### Permission Errors on /tmp
Ensure the application has write access to /tmp directory:
```bash
ls -la /tmp | head -5
chmod 777 /tmp  # If needed
```

## Monitoring

### PM2 Monitoring
```bash
# View application status
pm2 status

# View logs
pm2 logs voxnews-node-core

# Monitor in real-time
pm2 monit
```

### Manual Log Checking
```bash
# Last 50 lines of server output
tail -50 /var/log/nodejs/voxnews-node-core.log

# Watch logs in real-time
tail -f /var/log/nodejs/voxnews-node-core.log
```

## Performance Tuning

### Upload Size Limits
- Default: 25 MB per file
- Configured in `routes/documents.js`
- Adjust if needed for larger documents

### Processing Timeouts
- OCR timeout: 45 seconds
- TTS timeout: 30 seconds per request
- Adjust in service files if experiencing timeouts

### Memory Usage
```bash
# Monitor Node.js memory usage
ps aux | grep "node src/server.js"

# If memory issues occur, restart with increased heap
node --max-old-space-size=2048 src/server.js
```

## Security Notes

1. **API Key Management**
   - Store SARVAM_API_KEY securely in environment variables
   - Never commit to git
   - Rotate keys periodically

2. **CORS Configuration**
   - Currently allows all origins (wildcard)
   - Restrict in production: update `server.js` cors settings

3. **Helmet Headers**
   - Security headers are enabled
   - Allows cross-origin resource loading for asset pipelines

4. **File Uploads**
   - Files stored in `uploads/` directory
   - Implement virus scanning if needed
   - Clean up old uploads periodically

## Maintenance

### Regular Tasks
```bash
# Clear temporary Sarvam extraction directories
rm -rf /tmp/sarvam_*

# Clean node_modules cache (if needed)
npm cache clean --force

# Update dependencies (with caution)
npm update
```

### Backup Strategy
```bash
# Backup uploaded files
tar -czf uploads_backup_$(date +%Y%m%d).tar.gz uploads/

# Backup database (if using)
# (Configure based on your database setup)
```

## Support & Debugging

### Logs to Monitor
- Check `/tmp/server.log` or PM2 logs for startup errors
- Look for `[Sarvam Vision]` entries for OCR status
- Look for `[Sarvam TTS]` entries for audio generation
- Check `[process]` entries for document processing pipeline

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `EADDRINUSE: address already in use` | Port 8788 occupied | Kill existing process or change port |
| `SARVAM_API_KEY not configured` | Missing env variable | Add to .env and restart |
| `No audio data returned from Sarvam TTS` | API failure | Check API key validity and rate limits |
| `Invalid non-string/buffer chunk` | ZIP extraction error | Reinstall unzipper: `npm install unzipper` |

## Next Steps

1. ✅ Deploy code to Razorhost
2. ✅ Configure environment variables
3. ✅ Install dependencies
4. ✅ Start Node.js server
5. ⏭️ Configure Flutter app to use new endpoint
6. ⏭️ Set up monitoring and logging
7. ⏭️ Configure auto-restart on server reboot (PM2)

## Additional Resources

- [Sarvam AI Documentation](https://www.sarvam.ai/docs)
- [Express.js Guide](https://expressjs.com/)
- [PM2 Documentation](https://pm2.keymetrics.io/)
- [Node.js Best Practices](https://nodejs.org/en/docs/guides/)

---

**Last Updated**: 2026-05-23
**Version**: 1.0.0 (Sarvam AI Integration)
**Status**: ✅ Production Ready
