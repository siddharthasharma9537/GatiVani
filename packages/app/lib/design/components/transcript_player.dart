import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/transcript_sync_service.dart';
import '../../services/sentence_timing_service.dart';

/// Enhanced audio player with synchronized text display
/// Shows article text with current sentence highlighted
/// Tap text to jump audio playhead to that sentence
class TranscriptPlayer extends StatefulWidget {
  final String audioUrl;
  final String articleText;
  final VoidCallback onClose;

  const TranscriptPlayer({
    Key? key,
    required this.audioUrl,
    required this.articleText,
    required this.onClose,
  }) : super(key: key);

  @override
  State<TranscriptPlayer> createState() => _TranscriptPlayerState();
}

class _TranscriptPlayerState extends State<TranscriptPlayer> {
  late AudioPlayer _audioPlayer;
  late ScrollController _scrollController;
  late List<String> _sentences;
  late List<String> _words;
  late List<SentenceTiming> _sentenceTimings;
  late List<SentenceTiming> _wordTimings;
  int _currentSentenceIndex = 0;
  int _currentWordIndex = 0;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _useExactTiming = false;
  bool _useWordLevelSync = true;

  // Keys for each sentence to enable Scrollable.ensureVisible()
  late List<GlobalKey> _sentenceKeys;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _scrollController = ScrollController();
    _sentences = TranscriptSyncService.sentencesFromText(widget.articleText);
    _words = SentenceTimingService.wordsFromText(widget.articleText);

    // Create a key for each sentence for Scrollable.ensureVisible()
    _sentenceKeys = List.generate(_sentences.length, (_) => GlobalKey());

    // Build estimated timings (will be replaced with exact timings when available)
    _sentenceTimings = SentenceTimingService.buildEstimatedSentenceTimings(
      _sentences,
      Duration.zero,  // Will update once duration is loaded
    );
    _wordTimings = SentenceTimingService.buildEstimatedWordTimings(
      widget.articleText,
      Duration.zero,  // Will update once duration is loaded
    );
    _initAudioPlayer();
  }

  Future<void> _initAudioPlayer() async {
    try {
      print('[AudioPlayer] Initializing with URL: ${widget.audioUrl}');

      // Load the audio URL
      await _audioPlayer.setUrl(widget.audioUrl);
      print('[AudioPlayer] Audio URL set successfully');

      // Listen to position updates with responsive tracking
      _audioPlayer.positionStream.listen((position) {
        if (mounted) {
          int newSentenceIndex = _currentSentenceIndex;
          int newWordIndex = _currentWordIndex;

          if (_useWordLevelSync) {
            // Word-level sync (like Spotify lyrics highlighting individual words)
            newWordIndex = _useExactTiming
                ? SentenceTimingService.getIndexForPosition(
                    position,
                    _wordTimings,
                  )
                : SentenceTimingService.getIndexForPosition(
                    position,
                    _wordTimings,
                  );

            // Also track sentence for scrolling
            if (newWordIndex < _wordTimings.length) {
              final wordTiming = _wordTimings[newWordIndex];
              newSentenceIndex = _sentenceTimings.indexWhere(
                (s) => wordTiming.startTime >= s.startTime &&
                    wordTiming.startTime < s.endTime,
              );
              if (newSentenceIndex == -1) newSentenceIndex = 0;
            }
          } else {
            // Sentence-level sync (traditional, less precise)
            newSentenceIndex = _useExactTiming
                ? SentenceTimingService.getIndexForPosition(
                    position,
                    _sentenceTimings,
                  )
                : TranscriptSyncService.getCurrentSentenceIndex(
                    position,
                    _sentences,
                    _duration,
                  );
          }

          print('[Audio] Position: ${position.inSeconds}s, WordIndex: $newWordIndex, SentenceIndex: $newSentenceIndex');

          // Update state and scroll
          setState(() {
            _position = position;
            _currentWordIndex = newWordIndex;
            _currentSentenceIndex = newSentenceIndex;
          });

          // Schedule scroll update after build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateScroll();
          });
        }
      });

      _audioPlayer.playerStateStream.listen((state) {
        print('[AudioPlayer] Player state changed: playing=${state.playing}, processingState=${state.processingState}');
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
          });
        }
      });

      _audioPlayer.durationStream.listen((duration) {
        print('[AudioPlayer] Duration loaded: ${duration?.inSeconds}s');
        if (mounted) {
          setState(() {
            _duration = duration ?? Duration.zero;
            // Rebuild timings with accurate total duration
            _sentenceTimings = SentenceTimingService.buildEstimatedSentenceTimings(
              _sentences,
              _duration,
            );
            _wordTimings = SentenceTimingService.buildEstimatedWordTimings(
              widget.articleText,
              _duration,
            );
          });
        }
      });

      // Auto-play audio after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        print('[AudioPlayer] Auto-playing audio...');
        _audioPlayer.play().catchError((e) {
          print('[AudioPlayer] Error auto-playing: $e');
        });
      });

    } catch (e) {
      print('[AudioPlayer] Error initializing: $e');
    }
  }

  void _updateScroll() {
    if (_currentSentenceIndex < 0 || _currentSentenceIndex >= _sentenceKeys.length) {
      return;
    }

    try {
      // Use Scrollable.ensureVisible to scroll the current sentence into view
      // This automatically handles all scroll position calculations
      Scrollable.ensureVisible(
        _sentenceKeys[_currentSentenceIndex].currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5, // Center the item in viewport
      );
    } catch (e) {
      // Context might not be available yet during initial build
    }
  }

  void _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
    } catch (e) {
      // Silently fail
    }
  }

  void _jumpToSentence(int sentenceIndex) async {
    if (_sentences.isEmpty || _duration.inMilliseconds == 0) return;

    final position = _useExactTiming
        ? _sentenceTimings[sentenceIndex].startTime
        : Duration(
            milliseconds:
                (_duration.inMilliseconds * sentenceIndex / _sentences.length)
                    .toInt(),
          );
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      // Silently fail
    }
  }

  /// Set exact sentence timing metadata for perfect synchronization
  /// Call this after generating audio with sentence timing data
  void setExactSentenceTimings(
    List<SentenceTiming> timings,
  ) {
    setState(() {
      _sentenceTimings = timings;
      _useExactTiming = true;
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Build word-level sync - highlights individual words within sentences
  Widget _buildWordLevelSync() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_sentences.length, (sentenceIdx) {
        final sentenceWords = _sentences[sentenceIdx].split(RegExp(r'\s+'));
        final isSentenceCurrent = sentenceIdx == _currentSentenceIndex;

        return Container(
          key: _sentenceKeys[sentenceIdx],
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          color: isSentenceCurrent ? Colors.blue.withValues(alpha: 0.1) : Colors.transparent,
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: sentenceWords.asMap().entries.map((entry) {
              final wordIdx = entry.key;
              final word = entry.value;

              int globalWordIdx = 0;
              for (int i = 0; i < sentenceIdx; i++) {
                globalWordIdx += _sentences[i].split(RegExp(r'\s+')).length;
              }
              globalWordIdx += wordIdx;

              final isCurrentWord = globalWordIdx == _currentWordIndex;
              return Text(
                word,
                style: TextStyle(
                  color: isCurrentWord ? Colors.blue : Colors.black87,
                  fontWeight: isCurrentWord ? FontWeight.bold : FontWeight.normal,
                  fontSize: isCurrentWord ? 18 : 16,
                  backgroundColor: isCurrentWord ? Colors.blue.withValues(alpha: 0.2) : Colors.transparent,
                ),
              );
            }).toList(),
          ),
        );
      }),
    );
  }

  /// Build sentence-level sync - highlights entire sentences
  Widget _buildSentenceLevelSync() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_sentences.length, (index) {
        final isCurrent = index == _currentSentenceIndex;
        return Container(
          key: _sentenceKeys[index],
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          color: isCurrent ? Colors.blue.withValues(alpha: 0.1) : Colors.transparent,
          child: Text(
            _sentences[index],
            style: TextStyle(
              fontSize: 16,
              color: isCurrent ? Colors.blue : Colors.black87,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              height: 1.6,
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Controls
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Play/Pause and Sync Mode buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 32,
                    icon: Icon(
                      _isPlaying ? Icons.pause_circle : Icons.play_circle,
                    ),
                    onPressed: _togglePlayPause,
                  ),
                  const SizedBox(width: 16),
                  // Toggle between word and sentence sync
                  ActionChip(
                    label: Text(
                      _useWordLevelSync ? 'Word Sync' : 'Sentence Sync',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      setState(() {
                        _useWordLevelSync = !_useWordLevelSync;
                      });
                    },
                    backgroundColor: _useWordLevelSync
                        ? Colors.blue.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.2),
                  ),
                ],
              ),
              // Progress bar
              Slider(
                value: _position.inSeconds.toDouble(),
                max: _duration.inSeconds.toDouble(),
                onChanged: (value) {
                  _audioPlayer.seek(Duration(seconds: value.toInt()));
                },
              ),
              // Time display
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(_position)),
                  Text(_formatDuration(_duration)),
                ],
              ),
            ],
          ),
        ),
        // Synced text - word or sentence level
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Container(
              color: Colors.grey[50],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _useWordLevelSync
                  ? _buildWordLevelSync()
                  : _buildSentenceLevelSync(),
            ),
          ),
        ),
      ],
    );
  }
}
