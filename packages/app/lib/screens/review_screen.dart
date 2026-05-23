import 'package:flutter/material.dart';
import '../design/app_theme.dart';
import '../models/article.dart';
import '../services/sarvam_ai_service.dart';
import 'article_list_screen.dart';

class ReviewScreen extends StatefulWidget {
  final UploadedArticle article;

  const ReviewScreen({Key? key, required this.article}) : super(key: key);

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late TextEditingController _textController;
  bool _isGeneratingAudio = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.article.content);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose(); // ← fixed: was incorrectly calling super.initState()
  }

  Future<void> _saveAndPlay() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showError('No text to convert. Please add some content first.');
      return;
    }

    setState(() => _isGeneratingAudio = true);

    try {
      final sarvam = SarvamAIService();
      final audioUrl = await sarvam.generateAudioFromText(text, language: 'te-IN');

      final updatedArticle = widget.article.copyWith(
        content: text,
        audioUrl: audioUrl,
      );

      if (mounted) {
        // Navigate to article list screen (even for single articles)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ArticleListScreen(
              newspaperTitle: updatedArticle.source,
              newspaperDate: _formatDate(updatedArticle.extractedAt),
              language: 'Telugu',
              articles: [updatedArticle],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Audio generation failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isGeneratingAudio = false);
    }
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: GVColors.danger(context),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GVRadius.md)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wordCount =
        _textController.text.trim().split(RegExp(r'\s+')).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review extracted text'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '$wordCount words',
                style: GVTypography.small(context),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildArticleMeta(context),
            if (widget.article.truncated) _buildTruncationBanner(context),
            Divider(
                height: 1,
                thickness: 0.5,
                color: GVColors.borderTertiary(context)),
            Expanded(child: _buildEditor(context)),
            Divider(
                height: 1,
                thickness: 0.5,
                color: GVColors.borderTertiary(context)),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildArticleMeta(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: GVColors.accentBg(context),
              borderRadius: BorderRadius.circular(GVRadius.pill),
            ),
            child: Text(
              widget.article.category,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: GVColors.accent(context),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.article.title,
              style: GVTypography.small(context),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTruncationBanner(BuildContext context) {
    final p = widget.article.processedPages;
    final t = widget.article.totalPages;
    return Container(
      width: double.infinity,
      color: GVColors.warningBg(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: GVColors.warning(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Only $p of $t pages processed (${widget.article.tier} plan limit). Upgrade for more.',
              style: TextStyle(
                  fontSize: 12, color: GVColors.warning(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _textController,
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        style: GVTypography.reader(context),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          hintText: 'Extracted text will appear here. You can edit it before converting to audio.',
          hintStyle: GVTypography.bodySecondary(context),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _isGeneratingAudio ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isGeneratingAudio ? null : _saveAndPlay,
              icon: _isGeneratingAudio
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(
                  _isGeneratingAudio ? 'Generating audio...' : 'Save & play'),
            ),
          ),
        ],
      ),
    );
  }
}
