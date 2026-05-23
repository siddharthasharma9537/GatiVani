import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/article.dart';

/// Article player supporting both direct article data and articleId fetching.
/// Shows article image (or Gativani logo if unavailable)
/// Plays natural audio with optional text toggle
class ArticlePlayer extends StatefulWidget {
  // Direct article data (preferred)
  final String? audioUrl;
  final String? articleImageUrl;
  final String? articleText;
  final String? articleTitle;

  // Article ID for fetching (alternative)
  final String? articleId;
  final UploadedArticle? article;

  final VoidCallback onClose;

  const ArticlePlayer({
    Key? key,
    // Direct data constructor
    this.audioUrl,
    this.articleImageUrl,
    this.articleText,
    this.articleTitle,
    // Or pass article object
    this.article,
    // Or pass articleId (future: would fetch from API)
    this.articleId,
    required this.onClose,
  })  : assert(
          (audioUrl != null && articleTitle != null) ||
              article != null ||
              articleId != null,
          'Must provide either direct audio/title, article object, or articleId',
        ),
        super(key: key);

  @override
  State<ArticlePlayer> createState() => _ArticlePlayerState();
}

class _ArticlePlayerState extends State<ArticlePlayer> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _showText = false;
  UploadedArticle? _article;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initializeArticle();
  }

  Future<void> _initializeArticle() async {
    // If article object provided, use it directly
    if (widget.article != null) {
      setState(() => _article = widget.article);
      _initAudioPlayer();
      return;
    }

    // If direct audio/title provided, use legacy constructor
    if (widget.audioUrl != null && widget.articleTitle != null) {
      // Create a minimal article object for consistency
      _article = UploadedArticle(
        id: 'legacy',
        title: widget.articleTitle ?? '',
        content: widget.articleText ?? '',
        source: '',
        storageUrl: widget.articleImageUrl ?? '',
        category: '',
        audioUrl: widget.audioUrl ?? '',
        extractedAt: DateTime.now(),
      );
      _initAudioPlayer();
      return;
    }

    // If articleId provided, would fetch from API (future enhancement)
    if (widget.articleId != null) {
      setState(() => _isLoading = true);
      // TODO: Fetch article from API using articleId
      // For now, just show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Article fetching not yet implemented')),
        );
      }
    }
  }

  Future<void> _initAudioPlayer() async {
    if (_article?.audioUrl.isEmpty ?? true) {
      print('[AudioPlayer] No audio URL available');
      return;
    }

    try {
      final audioUrl = _article!.audioUrl;
      print('[AudioPlayer] Initializing with URL: $audioUrl');

      await _audioPlayer.setUrl(audioUrl);
      print('[AudioPlayer] Audio URL set successfully');

      _audioPlayer.positionStream.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });

      _audioPlayer.playerStateStream.listen((state) {
        print(
          '[AudioPlayer] Player state changed: playing=${state.playing}, processingState=${state.processingState}',
        );
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
          });
        }
      });

      // Auto-play audio
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

  void _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
    } catch (e) {
      print('Error toggling play/pause: $e');
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Colors.blue,
            ),
            const SizedBox(height: 16),
            const Text('Loading article...'),
          ],
        ),
      );
    }

    if (_article == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Failed to load article'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: widget.onClose,
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
    }

    final article = _article!;
    final hasAudio = article.audioUrl.isNotEmpty;
    final hasText = article.content.isNotEmpty;

    return Column(
      children: [
        // Close button
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  article.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        // Article image or logo
        Expanded(
          child: Container(
            color: Colors.grey[100],
            child: article.storageUrl.isNotEmpty
                ? Image.network(
                    article.storageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildGativaniLogo();
                    },
                  )
                : _buildGativaniLogo(),
          ),
        ),
        // Controls and text toggle
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Play/Pause button and text toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasAudio)
                    IconButton(
                      iconSize: 48,
                      icon: Icon(
                        _isPlaying ? Icons.pause_circle : Icons.play_circle,
                      ),
                      onPressed: _togglePlayPause,
                    )
                  else
                    IconButton(
                      iconSize: 48,
                      icon: const Icon(Icons.play_circle),
                      onPressed: null,
                    ),
                  const SizedBox(width: 24),
                  // Text toggle button
                  if (hasText)
                    FloatingActionButton.extended(
                      onPressed: () {
                        setState(() {
                          _showText = !_showText;
                        });
                      },
                      label: Text(_showText ? 'Hide Text' : 'Show Text'),
                      icon: Icon(_showText ? Icons.visibility_off : Icons.visibility),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Progress bar (only if audio available)
              if (hasAudio) ...[
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
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No audio available for this article',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
            ],
          ),
        ),
        // Optional text display
        if (_showText && hasText)
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                color: Colors.grey[50],
                padding: const EdgeInsets.all(16),
                child: Text(
                  article.content,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGativaniLogo() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Placeholder for Gativani logo
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.music_note,
                size: 60,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Gativani',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
