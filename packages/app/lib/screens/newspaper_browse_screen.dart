import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../design/app_theme.dart';
import '../models/newspaper_article.dart';
import '../services/audio_download_service.dart';
import 'audio_queue_player_screen.dart';

class NewspaperBrowseScreen extends StatefulWidget {
  final NewspaperResult newspaper;
  final String tier;

  const NewspaperBrowseScreen({
    Key? key,
    required this.newspaper,
    required this.tier,
  }) : super(key: key);

  @override
  State<NewspaperBrowseScreen> createState() => _NewspaperBrowseScreenState();
}

class _NewspaperBrowseScreenState extends State<NewspaperBrowseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<String> _categories;
  late List<NewspaperArticle> _articles;
  final Set<String> _downloadingIds = {};

  int get _selectedSeconds =>
      _articles.where((a) => a.isSelected).fold(0, (s, a) => s + a.estimatedDurationSeconds);

  int get _tierLimitSeconds => TierConfig.limitSeconds(widget.tier);

  bool get _overLimit =>
      !TierConfig.isUnlimited(widget.tier) && _selectedSeconds > _tierLimitSeconds;

  List<NewspaperArticle> get _selected => _articles.where((a) => a.isSelected).toList();

  @override
  void initState() {
    super.initState();
    _articles = widget.newspaper.articles.map((a) => a.copyWith()).toList();
    _categories = widget.newspaper.categories;
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toggleArticle(int index) {
    setState(() {
      _articles[index] = _articles[index].copyWith(isSelected: !_articles[index].isSelected);
    });
  }

  String _formatSeconds(int total) {
    if (total == 0) return '0 min';
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) return m == 0 ? '${h}h' : '${h}h ${m}m';
    if (m == 0) return '${s}s';
    return s == 0 ? '${m} min' : '${m}m ${s}s';
  }

  void _startListening() {
    if (_selected.isEmpty) {
      _snack('Select at least one article.');
      return;
    }
    if (_overLimit) {
      _snack('Selection exceeds your ${TierConfig.displayName[widget.tier] ?? widget.tier} limit.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioQueuePlayerScreen(articles: _selected, tier: widget.tier),
      ),
    );
  }

  void _downloadAll() {
    if (kIsWeb) {
      _snack('Downloads are not supported in the web version.');
      return;
    }
    final toDownload = _selected.where((a) => !a.isDownloaded).toList();
    if (toDownload.isEmpty) {
      _snack('All selected articles are already downloaded.');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GVColors.bgPrimary(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GVRadius.xl)),
        title: Text('Download ${toDownload.length} article${toDownload.length == 1 ? '' : 's'}',
            style: GVTypography.heading(context)),
        content: Text(
          'Audio will be generated and saved offline '
          '(${_formatSeconds(toDownload.fold(0, (s, a) => s + a.estimatedDurationSeconds))}). '
          'This uses your data connection.',
          style: GVTypography.bodySecondary(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: GVColors.textSecondary(context))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _runDownloads(toDownload);
            },
            child: Text('Download', style: TextStyle(color: GVColors.accent(context))),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadArticle(NewspaperArticle article) async {
    if (kIsWeb) {
      _snack('Downloads are not supported in the web version.');
      return;
    }
    if (article.isDownloaded || _downloadingIds.contains(article.id)) return;
    setState(() => _downloadingIds.add(article.id));
    try {
      final uri = await AudioDownloadService().downloadArticle(article, 'priya');
      final idx = _articles.indexWhere((a) => a.id == article.id);
      if (idx >= 0 && mounted) {
        setState(() {
          _articles[idx] = _articles[idx].copyWith(
            audioUrl: uri,
            isDownloaded: true,
            audioStatus: ArticleAudioStatus.ready,
          );
        });
      }
    } catch (e) {
      if (mounted) _snack('Download failed: ${article.title}');
    } finally {
      if (mounted) setState(() => _downloadingIds.remove(article.id));
    }
  }

  Future<void> _runDownloads(List<NewspaperArticle> articles) async {
    setState(() {
      for (final a in articles) _downloadingIds.add(a.id);
    });
    int success = 0;
    await Future.wait(articles.map((article) async {
      try {
        final uri = await AudioDownloadService().downloadArticle(article, 'priya');
        final idx = _articles.indexWhere((a) => a.id == article.id);
        if (idx >= 0 && mounted) {
          setState(() {
            _articles[idx] = _articles[idx].copyWith(
              audioUrl: uri,
              isDownloaded: true,
              audioStatus: ArticleAudioStatus.ready,
            );
            _downloadingIds.remove(article.id);
          });
          success++;
        }
      } catch (_) {
        if (mounted) setState(() => _downloadingIds.remove(article.id));
      }
    }));
    if (mounted) _snack('Downloaded $success of ${articles.length} articles.');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GVRadius.md)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GVColors.bgSecondary(context),
      appBar: AppBar(
        backgroundColor: GVColors.bgPrimary(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: GVColors.textPrimary(context),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.newspaper.title,
              style: GVTypography.heading(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.newspaper.date.isNotEmpty)
              Text(widget.newspaper.date, style: GVTypography.label(context)),
          ],
        ),
        actions: [
          if (_selected.isNotEmpty)
            IconButton(
              icon: Icon(Icons.download_outlined, color: GVColors.accent(context)),
              tooltip: 'Download selected',
              onPressed: _downloadAll,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: GVTypography.label(context).copyWith(fontWeight: FontWeight.w600),
          unselectedLabelStyle: GVTypography.label(context),
          labelColor: GVColors.accent(context),
          unselectedLabelColor: GVColors.textSecondary(context),
          indicatorColor: GVColors.accent(context),
          indicatorWeight: 2,
          dividerColor: GVColors.borderTertiary(context),
          tabs: _categories.map((cat) {
            final count = cat == 'All'
                ? _articles.length
                : _articles.where((a) => a.category == cat).length;
            return Tab(text: '$cat ($count)');
          }).toList(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _categories.map((cat) {
                final items = cat == 'All'
                    ? _articles
                    : _articles.where((a) => a.category == cat).toList();
                return _ArticleList(
                  articles: items,
                  allArticles: _articles,
                  onToggle: (article) {
                    final idx = _articles.indexWhere((a) => a.id == article.id);
                    if (idx >= 0) _toggleArticle(idx);
                  },
                  tierLimitSeconds: _tierLimitSeconds,
                  selectedSeconds: _selectedSeconds,
                  isUnlimited: TierConfig.isUnlimited(widget.tier),
                  formatSeconds: _formatSeconds,
                  onDownload: _downloadArticle,
                  downloadingIds: _downloadingIds,
                );
              }).toList(),
            ),
          ),
          _BottomBar(
            selected: _selected.length,
            totalSeconds: _selectedSeconds,
            tierLimitSeconds: _tierLimitSeconds,
            tierName: TierConfig.displayName[widget.tier] ?? widget.tier,
            isUnlimited: TierConfig.isUnlimited(widget.tier),
            overLimit: _overLimit,
            formatSeconds: _formatSeconds,
            onListen: _startListening,
          ),
        ],
      ),
    );
  }
}

// ── Article list ──────────────────────────────────────────────────────────────

class _ArticleList extends StatelessWidget {
  final List<NewspaperArticle> articles;
  final List<NewspaperArticle> allArticles;
  final void Function(NewspaperArticle) onToggle;
  final void Function(NewspaperArticle) onDownload;
  final Set<String> downloadingIds;
  final int tierLimitSeconds;
  final int selectedSeconds;
  final bool isUnlimited;
  final String Function(int) formatSeconds;

  const _ArticleList({
    required this.articles,
    required this.allArticles,
    required this.onToggle,
    required this.onDownload,
    required this.downloadingIds,
    required this.tierLimitSeconds,
    required this.selectedSeconds,
    required this.isUnlimited,
    required this.formatSeconds,
  });

  bool _wouldExceed(NewspaperArticle article) {
    if (isUnlimited || article.isSelected) return false;
    return selectedSeconds + article.estimatedDurationSeconds > tierLimitSeconds;
  }

  @override
  Widget build(BuildContext context) {
    if (articles.isEmpty) {
      return Center(
        child: Text('No articles in this category', style: GVTypography.bodySecondary(context)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: articles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final article = articles[i];
        final wouldExceed = _wouldExceed(article);
        return _ArticleCard(
          article: article,
          wouldExceed: wouldExceed,
          isDownloading: downloadingIds.contains(article.id),
          onToggle: () => onToggle(article),
          onDownload: () => onDownload(article),
          formatSeconds: formatSeconds,
        );
      },
    );
  }
}

// ── Single article card ───────────────────────────────────────────────────────

class _ArticleCard extends StatelessWidget {
  final NewspaperArticle article;
  final bool wouldExceed;
  final bool isDownloading;
  final VoidCallback onToggle;
  final VoidCallback onDownload;
  final String Function(int) formatSeconds;

  const _ArticleCard({
    required this.article,
    required this.wouldExceed,
    required this.isDownloading,
    required this.onToggle,
    required this.onDownload,
    required this.formatSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final catColor = GVCategory.color(article.category);
    final isSelected = article.isSelected;

    return InkWell(
      onTap: wouldExceed && !isSelected ? null : onToggle,
      borderRadius: BorderRadius.circular(GVRadius.lg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? GVColors.accentBg(context) : GVColors.bgPrimary(context),
          border: Border.all(
            color: isSelected ? GVColors.accent(context) : GVColors.borderTertiary(context),
            width: isSelected ? 1.5 : 0.5,
          ),
          borderRadius: BorderRadius.circular(GVRadius.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category accent bar
            Container(
              width: 4,
              height: 80,
              margin: const EdgeInsets.only(left: 0),
              decoration: BoxDecoration(
                color: catColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(GVRadius.lg),
                  bottomLeft: Radius.circular(GVRadius.lg),
                ),
              ),
            ),
            // Checkbox
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 10, right: 0),
              child: Checkbox(
                value: isSelected,
                onChanged: (wouldExceed && !isSelected) ? null : (_) => onToggle(),
                activeColor: GVColors.accent(context),
                side: BorderSide(color: GVColors.borderSecondary(context)),
                visualDensity: VisualDensity.compact,
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: catColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(GVRadius.sm),
                      ),
                      child: Text(
                        article.category,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: catColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    // Title
                    Text(
                      article.title,
                      style: GVTypography.body(context).copyWith(
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? GVColors.accent(context)
                            : GVColors.textPrimary(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Preview
                    Text(
                      article.preview,
                      style: GVTypography.small(context),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Duration + exceed warning
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: 12, color: GVColors.textTertiary(context)),
                        const SizedBox(width: 3),
                        Text(
                          formatSeconds(article.estimatedDurationSeconds),
                          style: GVTypography.label(context),
                        ),
                        if (wouldExceed && !isSelected) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.warning_amber_rounded,
                              size: 12, color: GVColors.warning(context)),
                          const SizedBox(width: 3),
                          Text(
                            'Exceeds limit',
                            style: GVTypography.label(context)
                                .copyWith(color: GVColors.warning(context)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Per-article download button
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 10, 0),
              child: isDownloading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: GVColors.accent(context),
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        article.isDownloaded
                            ? Icons.download_done_rounded
                            : Icons.download_outlined,
                        size: 18,
                        color: article.isDownloaded
                            ? GVColors.success(context)
                            : GVColors.textTertiary(context),
                      ),
                      tooltip: article.isDownloaded ? 'Saved offline' : 'Download',
                      onPressed: article.isDownloaded ? null : onDownload,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sticky bottom bar ─────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final int selected;
  final int totalSeconds;
  final int tierLimitSeconds;
  final String tierName;
  final bool isUnlimited;
  final bool overLimit;
  final String Function(int) formatSeconds;
  final VoidCallback onListen;

  const _BottomBar({
    required this.selected,
    required this.totalSeconds,
    required this.tierLimitSeconds,
    required this.tierName,
    required this.isUnlimited,
    required this.overLimit,
    required this.formatSeconds,
    required this.onListen,
  });

  @override
  Widget build(BuildContext context) {
    final progress = isUnlimited
        ? 0.0
        : (totalSeconds / tierLimitSeconds).clamp(0.0, 1.0);
    final canListen = selected > 0 && !overLimit;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: GVColors.bgPrimary(context),
        border: Border(
          top: BorderSide(color: GVColors.borderTertiary(context), width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stats row
          Row(
            children: [
              Text(
                selected == 0
                    ? 'No articles selected'
                    : '$selected article${selected == 1 ? '' : 's'} · ${formatSeconds(totalSeconds)}',
                style: GVTypography.small(context).copyWith(
                  fontWeight: FontWeight.w500,
                  color: overLimit
                      ? GVColors.danger(context)
                      : GVColors.textPrimary(context),
                ),
              ),
              const Spacer(),
              Text(
                isUnlimited ? 'Unlimited' : 'Limit: ${formatSeconds(tierLimitSeconds)}',
                style: GVTypography.label(context),
              ),
            ],
          ),
          // Tier progress bar
          if (!isUnlimited) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(GVRadius.pill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: GVColors.bgTertiary(context),
                valueColor: AlwaysStoppedAnimation<Color>(
                  overLimit ? GVColors.danger(context) : GVColors.accent(context),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Start listening button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canListen ? onListen : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                selected == 0
                    ? 'Select articles to listen'
                    : overLimit
                        ? 'Exceeds $tierName limit'
                        : 'Start Listening',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: GVColors.accent(context),
                disabledBackgroundColor: GVColors.bgTertiary(context),
                foregroundColor: Colors.white,
                disabledForegroundColor: GVColors.textTertiary(context),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GVRadius.lg)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
