# GatiVani Feature Analysis: Content Upload & AI Categorization
**Date:** 2026-05-11  
**Status:** Feature Analysis & Implementation Plan

---

## 🎯 **FEATURE REQUEST SUMMARY**

User wants to add capability to upload content (PDF/Photos/URL) and have the app:
1. Extract text via OCR (Sarvam AI)
2. Categorize content using AI
3. Provide summaries in Telugu-English bilingual format
4. Track user preferences via "Like" button
5. Personalize article display based on preferences

---

## ✅ **ANALYSIS & REFINEMENT**

### **What's Good About This Feature**

| Aspect | Benefit |
|--------|---------|
| **User Agency** | Users can add custom content beyond built-in newspaper sources |
| **Multi-Modal Input** | PDF + Camera + URL covers most use cases |
| **OCR Integration** | Sarvam AI already integrated; reusable |
| **AI Categorization** | Adds intelligence + personalization |
| **Bilingual Support** | Serves Telugu + English audience |
| **Preference Learning** | Like/Unlike creates user profile for recommendations |

### **What Needs Refinement**

| Challenge | Solution |
|-----------|----------|
| **OCR Accuracy** | PDFs/photos have varying quality; need fallback + user correction |
| **AI Categorization Complexity** | Too many micro-categories; consolidate into 7-8 major ones |
| **Real-Time Categorization Cost** | Gemini API calls expensive; batch + cache categories |
| **Bilingual Summarization** | Gemini → Telugu via SarvamAI TTS, but English summaries native |
| **User Preference Signal** | "Like" alone insufficient; track article view duration, clicks |
| **UI/UX Complexity** | New screen for upload modal, OCR preview, review flow |
| **Backend Persistence** | Store uploaded articles, OCR results, categories, preferences |

---

## 🎨 **REFINED FEATURE SPECIFICATION**

### **Phase 1: Core Upload & OCR (MVP)**

**User Flow:**
1. User taps "+" on Home → shows modal with 3 options
2. **Option A: PDF** → File picker → Upload to Firebase Storage
3. **Option B: Camera/Photos** → Native camera/gallery → Capture image
4. **Option C: URL** → Text input → Fetch webpage content
5. **OCR Processing** → Sarvam AI extracts text
6. **Review Screen** → User reviews extracted text, can edit/correct
7. **Store** → Save original + extracted content

**Implementation:**
- New screen: `lib/screens/upload_content_screen.dart`
- Upload modal: `lib/design/components/upload_modal.dart`
- OCR service: Already have `SarvamAIService.extractTextFromImage()`
- Storage: Firebase Storage + Firestore for metadata
- UI: WebView for URL preview (optional)

**API Calls:**
- SarvamAI OCR: €0.01 per page (batch optimize)
- Firebase Storage: €0.018/GB (free 5GB tier covers demo)
- No additional cost for this phase

---

### **Phase 2: AI Categorization (Week 2-3)**

**Refined Categories (8 instead of 15+):**
1. **National News** — Politics, national policies, PM/ministers
2. **State & Local** — State govt, district news, city updates
3. **Crime & Law** — Crime reports, court orders, legal news
4. **Business & Economy** — Markets (NSE, BSE, Nifty), corporate, startups
5. **Science & Technology** — Tech news, innovations, gadgets
6. **Sports & Entertainment** — Cricket, cinema, celebrities, entertainment
7. **Social & Health** — Govt schemes, health, education, social issues
8. **Opinion & Editorial** — Editorials, columns, analysis

**Implementation:**
- Create categorization prompt for Gemini: Extract 2-3 top categories + confidence
- Cache results: Store category in Firestore for each article
- User override: Allow user to re-categorize if AI gets it wrong

**Example Prompt for Gemini:**
```
Analyze this article and provide:
1. Primary category (highest confidence)
2. Secondary category (if applicable)
3. Confidence score (0-100)

Categories: National News, State & Local, Crime & Law, Business & Economy, 
Science & Technology, Sports & Entertainment, Social & Health, Opinion & Editorial

Article: [extracted text]

Return JSON: {"primary": "...", "secondary": "...", "confidence": 85}
```

**Cost:**
- Gemini API: ~€0.0005 per categorization (minimal)

---

### **Phase 3: Summarization & TTS (Week 3)**

**Bilingual Summarization Strategy:**

| Language | Method | Cost | Quality |
|----------|--------|------|---------|
| **English** | Gemini (native) | ~€0.0005/call | Excellent |
| **Telugu** | English → Telugu via Gemini or SarvamAI | ~€0.001/call | Good |

**Implementation:**
- English Summary: Gemini Pro (60-80 words)
- Telugu Summary: 
  - **Option A (Cheaper):** Translate English summary to Telugu via Gemini
  - **Option B (Better):** Have Gemini generate Telugu summary directly
  - **Option C (Best):** Use SarvamAI TTS on English summary as fallback

**Recommended: Option A + B hybrid**
- Primary: Gemini generates Telugu summary directly
- Fallback: Translate English summary if Telugu fails

**Implementation:**
- Service: `GeminiService.generateBilingualSummary()`
- TTS: `SarvamAIService.textToSpeech()` (already have)

---

### **Phase 4: User Preference Learning (Week 4)**

**Preference Signals to Track:**

| Signal | Weight | Implementation |
|--------|--------|-----------------|
| **Like Button** | 40% | Simple UI button, store in Firestore |
| **View Duration** | 30% | Analytics event when article viewed >10s |
| **Category Clicks** | 20% | Track which category articles user opens |
| **Share Count** | 10% | Analytics when user shares article |

**Implementation:**
- Add `UserPreference` model: `{userId, categories_liked: {}, articles_liked: []}`
- Add analytics events: `article_viewed`, `article_liked`, `article_shared`
- Firebase Analytics already integrated
- Home screen recommends: Sort articles by user's top 3 liked categories

**UI Changes:**
- Add ❤️ Like button on each article card
- Show liked categories in profile/settings
- Home screen: "Recommended for you" section based on likes

---

### **Phase 5: Home Screen Integration (Week 4)**

**New Home Screen Layout:**

```
┌─────────────────────────────┐
│  GatiVani                 + │  ← "+" button (top-right)
├─────────────────────────────┤
│ 📰 Filter: All | National   │
│            State | Business │
├─────────────────────────────┤
│ ✨ Recommended For You      │  ← Based on likes
│ ┌─────────────────────────┐ │
│ │ Article 1 (Your fav)    │ │
│ │ [Image] Headline... ❤️  │ │
│ └─────────────────────────┘ │
│                             │
│ 📰 News Feed                │
│ ┌─────────────────────────┐ │
│ │ Article 2               │ │
│ │ [Image] Headline... 🤍  │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

**"+" Button Modal:**
```
┌──────────────────────────┐
│  Add Content             │
├──────────────────────────┤
│                          │
│  [📄 Upload PDF]         │
│  [📷 Camera/Photos]      │
│  [🔗 Paste URL]          │
│                          │
│  [Cancel]                │
└──────────────────────────┘
```

---

## 📊 **IMPLEMENTATION ROADMAP**

### **Week 1: Upload & OCR (MVP)**
- New upload screen + modal UI
- PDF/photo/URL file handling
- SarvamAI OCR integration (reuse existing)
- OCR review/edit screen
- Firebase Storage upload
- Firestore metadata storage

**Estimated:** 16 hours  
**Files to create:** 4-5 new Dart files

### **Week 2: Categorization**
- Gemini categorization prompt engineering
- Category caching in Firestore
- Category display on articles
- Category filtering in home screen

**Estimated:** 8 hours  
**Files to create:** 2-3 new files

### **Week 3: Summarization & TTS**
- Bilingual summarization (Gemini)
- SarvamAI TTS for Telugu
- Summary display in article detail
- Playback UI

**Estimated:** 6 hours  
**Files to modify:** 2-3 existing files

### **Week 4: Preference Learning & Integration**
- Like/Unlike button UI
- Firebase Analytics events
- User preference model + Firestore
- Home screen recommendation algorithm
- Settings page for preference management

**Estimated:** 12 hours  
**Files to create:** 3-4 new files

---

## 💰 **COST ANALYSIS**

### **Additional API Costs (Monthly)**

| Service | Usage | Cost |
|---------|-------|------|
| **Sarvam AI OCR** | ~100 PDFs/photos/month | ~€1.00 |
| **Gemini Categorization** | ~100 articles | ~€0.05 |
| **Gemini Summarization** | ~100 articles | ~€0.05 |
| **Firebase Storage** | ~1GB/month uploads | Free (5GB tier) |
| **Firebase Firestore** | ~1000 reads/writes | Free (free tier) |
| **Firebase Analytics** | Unlimited | Free |
| **SarvamAI TTS** | ~100 summaries | ~€2.00 |
| **TOTAL** | — | **~€3.10/month** |

**Current monthly cost: ~€25-30**  
**New total: ~€28-33/month** ✅ **Still budget-friendly**

---

## 🎯 **BEST IMPLEMENTATION STRATEGY**

### **Recommended Approach: Phased MVP → Full Feature**

#### **Phase 1 (Week 1): Minimal Viable Product**
- ✅ Upload PDF/Photos/URL
- ✅ Extract text via OCR
- ✅ Store in Firestore
- ✅ Display as new "article" card
- ❌ No categorization yet
- ❌ No summarization yet
- ❌ No likes yet

**Why:** Validate feature demand before adding complexity

#### **Phase 2 (Week 2-4): Full Feature**
- ✅ Phase 1 + Categorization
- ✅ Bilingual summaries
- ✅ Like button + preference learning
- ✅ Personalized recommendations

### **Technical Stack for New Feature**

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **File Upload** | `file_picker` + Firebase Storage | Native support, simple |
| **Camera/Photos** | `image_picker` | Flutter standard library |
| **URL Fetching** | `http` package | Lightweight content fetch |
| **OCR** | SarvamAI (existing) | Already integrated |
| **Categorization** | Gemini API (existing) | Already integrated |
| **Summarization** | Gemini API (existing) | Already integrated |
| **TTS** | SarvamAI TTS (existing) | Already integrated |
| **Storage** | Firebase Storage + Firestore | Already integrated |
| **Preference Tracking** | Firebase Analytics (existing) | Already integrated |

---

## 🚨 **Potential Challenges & Solutions**

| Challenge | Solution | Priority |
|-----------|----------|----------|
| **OCR Quality (blurry photos)** | Show confidence score, allow manual text editing | High |
| **Category Hallucination** | Validate Gemini output, allow user override | Medium |
| **Summarization Quality** | Use few-shot prompt examples, review summaries | Medium |
| **Firestore Quota (free tier)** | Batch writes, cache aggressively | Low (not immediate issue) |
| **Large PDF Processing** | Split large PDFs into pages, process per-page | High |
| **User Privacy** | Don't store full PDF content; hash for dedup | Medium |

---

## 📋 **ACTION ITEMS**

### **Immediate (Next Sprint)**

1. **Create Feature Branch**
   ```bash
   git checkout -b feature/content-upload
   ```

2. **Implement Phase 1 (Week 1)**
   - [ ] Add pubspec dependencies (`file_picker`, `image_picker`, `http`)
   - [ ] Create upload modal UI
   - [ ] Create upload content screen
   - [ ] Wire up file/camera/URL handlers
   - [ ] Test OCR with sample PDFs

3. **Create Feature Planning Document**
   - [ ] User stories for each phase
   - [ ] Wire frames for upload flow
   - [ ] Test cases for OCR accuracy

4. **Schedule Review**
   - [ ] Show Phase 1 MVP to user
   - [ ] Get feedback before proceeding to Phase 2

---

## 🎨 **DESIGN MOCKUPS (Text Description)**

### **Upload Modal (Phase 1)**
```
Modal appears when "+" tapped:
- Title: "Add Content"
- 3 large buttons:
  - 📄 Upload PDF — Tap to pick PDF from device
  - 📷 Camera/Photos — Tap to open camera or gallery
  - 🔗 Paste URL — Text input field
- Cancel button at bottom
```

### **OCR Review Screen (Phase 1)**
```
After OCR completes:
- Show extracted text in scrollable text area
- User can edit/correct text before saving
- "Confidence: 87%" badge shows OCR confidence
- Save button confirms, Cancel discards
```

### **Article Card with Like (Phase 4)**
```
Card layout:
- [Image]
- Headline (truncated)
- Source + Category badge
- Summary preview (3 lines)
- ❤️ Like button (toggles when tapped)
- Read more button
```

### **Recommended Section (Phase 4)**
```
Home screen new section:
- "✨ Recommended For You" header
- Shows articles from user's top liked categories
- Sorted by recency within preferred categories
- "Learn more" link to preference settings
```

---

## ✨ **SUCCESS CRITERIA**

### **Phase 1 (MVP)**
- [ ] User can upload PDF/photo and see extracted text
- [ ] OCR confidence displayed
- [ ] Extracted content stored in Firestore
- [ ] New articles appear in home feed

### **Phase 2**
- [ ] Articles automatically categorized
- [ ] Categories shown on cards
- [ ] Users can filter by category

### **Phase 3**
- [ ] English summaries generated
- [ ] Telugu summaries generated or translated
- [ ] TTS plays summaries in both languages

### **Phase 4**
- [ ] Like button works and stores preference
- [ ] Home screen shows "Recommended For You"
- [ ] Articles sorted by user preference

---

## 📝 **SUMMARY**

**Best Implementation Strategy: Phased MVP Approach**

1. **Start with Phase 1 (1 week):** Upload + OCR only
   - Get user feedback before investing more
   - Validate demand for the feature
   - Keep code simple and maintainable

2. **Then Phase 2-4 (3 weeks):** Full feature with AI categorization, summaries, and personalization
   - Build on proven Phase 1
   - Cost remains budget-friendly (~€3/month additional)
   - Leverages existing APIs (all already integrated)

3. **Key Advantages:**
   - ✅ Uses existing services (no new API integrations)
   - ✅ Minimal cost increase
   - ✅ High user engagement potential
   - ✅ Phased approach reduces risk
   - ✅ Reuses existing SarvamAI, Gemini, Firebase

4. **Recommended Timeline:**
   - Week 1: Phase 1 MVP → User feedback
   - Week 2-4: Phase 2-4 full feature → Launch

---

**Ready to proceed with Phase 1 implementation?** 🚀
