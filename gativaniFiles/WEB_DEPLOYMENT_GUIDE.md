# GatiVani Web Preview - Vercel Deployment Guide

## 🚀 Quick Start (5 minutes)

### Prerequisites
- ✅ Flutter 3.0+ installed locally
- ✅ Git configured
- ✅ Vercel account (free tier works)

### Step 1: Build Flutter Web Locally

```bash
cd packages/app

# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Build web optimized
flutter build web --release --web-renderer html
```

**Output**: `build/web/` directory with all static files

### Step 2: Prepare for Vercel

The `vercel.json` is already configured. Just ensure:

```bash
# From repo root, check if vercel.json exists
cat vercel.json

# Expected content:
# - buildCommand: Flutter web build
# - outputDirectory: build/web
# - SPA rewrites enabled
# - Security headers configured
```

### Step 3: Deploy to Vercel

#### Option A: Vercel CLI (Easiest)

```bash
# Install Vercel CLI (one-time)
npm i -g vercel

# From repo root
vercel

# Follow prompts:
# - Link to existing project? No (create new)
# - Project name: gativani-web
# - Framework: Other (since it's Flutter)
# - Output directory: build/web
```

#### Option B: GitHub Integration (Recommended)

1. **Push code to GitHub** (already there):
   ```bash
   git add vercel.json
   git commit -m "Add Vercel web deployment config"
   git push origin main
   ```

2. **Connect to Vercel**:
   - Go to [vercel.com/new](https://vercel.com/new)
   - Select `siddharthasharma9537/GatiVani` repo
   - Framework: Other
   - Build Command: `cd packages/app && flutter build web --release`
   - Output Directory: `packages/app/build/web`
   - Click Deploy

3. **Auto-deploy on push**: Every git push will trigger new build

#### Option C: Docker Build (Advanced)

If local Flutter build is slow:

```bash
# Use Flutter Docker image
docker run --rm \
  -v $(pwd):/workspace \
  -w /workspace/packages/app \
  google/flutter:latest \
  flutter build web --release

# Build output → packages/app/build/web/
```

### Step 4: Verify Deployment

```bash
# After deployment completes, test:
curl https://your-vercel-url.vercel.app/

# Should return index.html with Flutter web app
```

---

## 🔧 Environment Configuration

### .env Files for Web

The app supports multiple environments:

**Development** (`.env.development`)
```
BACKEND_URL=http://localhost:8788
FIREBASE_PROJECT_ID=gativani-dev
SARVAM_API_KEY=<dev-key>
```

**Production** (`.env.production`)
```
BACKEND_URL=https://gativani.sohum.cloud
FIREBASE_PROJECT_ID=gativani-prod
SARVAM_API_KEY=<prod-key>
```

**Vercel Environment Variables**:
- Go to Vercel Project Settings → Environment Variables
- Add the production env vars for `prod`, `preview`, `development`
- Flutter will auto-load based on build mode

---

## 🌐 API Integration

### Backend URL Configuration

The Flutter app connects to Node.js backend at:
- **Dev**: `http://localhost:8788`
- **Prod**: `https://gativani.sohum.cloud`

**CORS Configuration** (already enabled in backend):
```javascript
// packages/core/src/server.js
cors: { origin: '*' }
```

### API Endpoints Available

```
POST /api/documents/process
  Upload newspaper → Get articles + audio

POST /api/documents/synthesize
  Text → Audio in Telugu/Hindi/English

GET /health
  Backend health check
```

---

## 📊 Performance Tips

### 1. Enable Gzip Compression
Already configured in `vercel.json` with Cache-Control headers.

### 2. Minimize App Size

```bash
# Build with optimization
flutter build web --release \
  --web-renderer html \
  --dart-define=FLUTTER_WEB_RELEASE=true
```

**Expected size**: 15-25 MB (first load)

### 3. Cache Strategy

```
Static files: 1 hour cache
index.html: No cache (always fresh)
API calls: Handled by backend
```

---

## 🐛 Troubleshooting

### Build Fails on Vercel

**Error**: `flutter: command not found`
- **Solution**: Use GitHub Actions to pre-build, then deploy

### CORS Issues

**Error**: `Access to XMLHttpRequest blocked`
- **Solution**: Backend already has CORS enabled
- **Check**: `curl -i https://your-backend/health`

### Large Build Size

**Error**: `Build exceeded time limit`
- **Solution**: 
  ```bash
  flutter build web --release \
    --split-debug-info=debug_info \
    --obfuscate
  ```

### API Not Responding

**Error**: `Cannot POST /api/documents/process`
- **Check**: 
  ```bash
  echo $BACKEND_URL  # Verify env var
  curl $BACKEND_URL/health  # Test connectivity
  ```

---

## 📝 Vercel.json Breakdown

```json
{
  // Flutter builds to build/web
  "buildCommand": "...",
  "outputDirectory": "build/web",
  
  // Environment setup
  "env": {
    "NODE_ENV": "production"
  },
  
  // Security headers
  "headers": [{
    "key": "X-Content-Type-Options",
    "value": "nosniff"
  }],
  
  // SPA routing - all routes → index.html
  "rewrites": [{
    "source": "/(.*)",
    "destination": "/index.html"
  }]
}
```

---

## 🚦 Deployment Status Checklist

- [ ] Flutter web builds locally without errors
- [ ] `vercel.json` exists in repo root
- [ ] GitHub repo is public
- [ ] Vercel account created (free)
- [ ] Project connected to Vercel
- [ ] Build succeeds on first deploy
- [ ] Live URL accessible
- [ ] Backend API responds (check /health)
- [ ] Upload newspaper → Get articles
- [ ] Audio playback works

---

## 📱 Testing the MVP

### On Web
1. Visit `https://your-vercel-url.vercel.app/`
2. You should see GatiVani app UI
3. Try uploading a test newspaper PDF
4. Should extract articles and generate audio

### Required Test Files
- `test.pdf` or any Indian newspaper (Telugu, Hindi)
- Should be 1-5 pages for quick processing
- Sample: `eenadu_test1.pdf` (included in repo)

---

## 🔐 Security Checklist

- ✅ API keys in Vercel Secrets (not in code)
- ✅ CORS configured for specific origins (optional)
- ✅ Helmet security headers enabled
- ✅ Firebase authentication if needed
- ✅ Rate limiting on backend (if using production)

---

## 📊 Next Steps Post-Launch

1. **Monitor Performance**: Vercel Analytics
2. **Track Errors**: Firebase Crashlytics
3. **Scale Backend**: If getting 100+ daily users
4. **Add Analytics**: Google Analytics 4 integration
5. **Mobile App**: Link web preview URL in app for testing

---

## 🆘 Support Resources

- [Flutter Web Documentation](https://flutter.dev/docs/get-started/web)
- [Vercel Deployment Docs](https://vercel.com/docs)
- [GatiVani GitHub Issues](https://github.com/siddharthasharma9537/GatiVani/issues)

---

**Last Updated**: 2026-06-05
**Vercel.json Version**: 1.0
**Status**: Ready for deployment
