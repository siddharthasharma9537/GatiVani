# Perfect Audio-Text Synchronization Implementation Guide

**Problem:** Music apps have perfect lyrics sync because they have metadata about when each lyric starts/ends. Our app was guessing sentence positions based on linear distribution, causing lag or drift.

**Solution:** Capture exact timing information when generating TTS audio.

---

## Architecture

### Current State (Estimation-based)
```
Text → Split into sentences → Estimate timing based on total duration
Result: ±500ms drift, especially with variable sentence lengths
```

### Target State (Exact Timing)
```
Text → Split sentences → Generate audio for each sentence → Track cumulative time
Result: Perfect sync, <50ms drift (like music app lyrics)
```

---

## Implementation Steps

### Phase 1: Infrastructure (✅ DONE)

Created two new services:

1. **SentenceTimingService** (`sentence_timing_service.dart`)
   - Stores exact start/end times for each sentence
   - Binary search for efficient lookup
   - Fallback to estimated timings when metadata unavailable

2. **TranscriptPlayer** (updated)
   - Uses `SentenceTimingService` for exact timing
   - Falls back to `TranscriptSyncService` estimation
   - `setExactSentenceTimings()` method to enable perfect sync

### Phase 2: TTS Generation with Timing (TODO)

Modify TTS to return timing metadata:

**Sarvam AI API** — Check if the TTS response includes timing data:
```dart
// In sarvam_ai_service.dart, modify generateAudioFromText():
final response = await http.post(...);
final data = jsonDecode(response.body);

// Check for timing in response:
// data['sentence_timings'] or similar structure
if (data['sentence_timings'] != null) {
  // Return both audio URL and timing metadata
  return {
    'audioUrl': audioUrl,
    'sentenceTimings': data['sentence_timings'],
  };
}
```

**Fallback Approach** — If Sarvam AI doesn't provide timing:
```dart
// Generate audio sentence-by-sentence and track timing
// 1. Split text into sentences
// 2. For each sentence, call TTS separately
// 3. Track cumulative duration
// 4. Assemble final audio from chunks

List<SentenceTimingService.SentenceTiming> buildTimingMetadata(
  List<String> sentences,
  List<Duration> sentenceDurations,
) {
  final timings = <SentenceTimingService.SentenceTiming>[];
  int cumulativeMs = 0;

  for (int i = 0; i < sentences.length; i++) {
    final startMs = cumulativeMs;
    final endMs = cumulativeMs + sentenceDurations[i].inMilliseconds;

    timings.add(SentenceTimingService.SentenceTiming(
      text: sentences[i],
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: endMs),
    ));

    cumulativeMs = endMs;
  }

  return timings;
}
```

### Phase 3: Update Player Integration (TODO)

When audio is generated with timing metadata:

```dart
// In player_screen.dart or wherever audio is generated:

final audioData = await sarvamService.generateAudioFromText(
  articleText,
  captureTimings: true,  // Flag for new method
);

// If timings available, enable perfect sync:
if (audioData['sentenceTimings'] != null) {
  final timings = (audioData['sentenceTimings'] as List)
      .map((t) => SentenceTimingService.SentenceTiming.fromJson(t))
      .toList();

  transcriptPlayerKey.currentState?.setExactSentenceTimings(timings);
}
```

---

## Sync Quality Comparison

| Metric | Current (Estimation) | With Exact Timing |
|--------|----------------------|-------------------|
| **Accuracy** | ±500ms drift | <50ms drift |
| **Variable Lengths** | Oscillates | Stable |
| **Speaking Pauses** | Misses timing | Perfect |
| **Feel** | Slightly lagging/ahead | Like native music apps |

---

## Testing

### Before Sync Implementation
```bash
flutter run
# Play audio, observe: text lags behind or jumps ahead
```

### After Sync Implementation
```bash
flutter run
# Play audio, observe: text stays perfectly in sync with audio
```

**Test Scenarios:**
- [ ] Short sentences (5 words)
- [ ] Long sentences (50+ words)
- [ ] Mixed lengths
- [ ] Fast speaking
- [ ] Slow speaking
- [ ] With pauses

---

## API Integration Checklist

### Sarvam AI TTS API
- [ ] Check official docs for timing metadata support
- [ ] If not available, add batch endpoint to your backend
- [ ] Return timing info alongside audio URL

### Backend (packages/core/)
- [ ] Create `/api/documents/process-with-timings` endpoint
- [ ] Accept text, return audio URL + sentence timings
- [ ] Cache timing metadata with audio

### Frontend (packages/app/)
- [ ] Detect timing metadata availability
- [ ] Fall back to estimation if unavailable
- [ ] Store timings for offline playback

---

## Fallback Strategy

If Sarvam AI doesn't provide timing:

**Option A: Batch TTS (Best)**
- Send each sentence to TTS separately
- Collect results and timings
- Merge audio files
- Use exact timings

**Option B: Server-side Timing (Medium)**
- Send full text to TTS
- Have backend estimate timings based on word count
- Return estimation with audio

**Option C: Client-side Estimation (Current)**
- Use `SentenceTimingService.buildEstimatedTimings()`
- Accuracy: ±500ms
- Better than nothing!

---

## Future Improvements

1. **Word-level Sync** — Instead of sentences, sync individual words
   - Like YouTube captions
   - Requires word-level timing from TTS

2. **Adaptive Timing** — Adjust for speaking speed variations
   - Detect sudden speed changes
   - Recalibrate mid-playback

3. **Confidence Scores** — Track sync confidence
   - High confidence: exact timing available
   - Medium: estimated from word count
   - Low: linear estimation

---

## Current Status

✅ **Infrastructure ready**
- SentenceTimingService implemented
- TranscriptPlayer supports exact timing
- Fallback to estimation works

⏳ **Awaiting**
- Sarvam AI API timing metadata check
- Backend integration for timing generation
- Frontend TTS modification

---

## Questions to Investigate

1. **Does Sarvam AI TTS return timing data in response?**
   Check: `data['timing']`, `data['metadata']`, `data['sentence_times']`

2. **Can we add sentence-level TTS generation?**
   Pros: Exact timing, cache-friendly
   Cons: More API calls, slower

3. **Should we cache timing metadata?**
   Yes: Store with audio URL for offline playback

