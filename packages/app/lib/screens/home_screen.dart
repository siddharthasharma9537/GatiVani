import 'package:flutter/material.dart';
import '../design/app_theme.dart';
import '../config/api_config.dart';
import 'upload_content_screen.dart';
import 'player_screen.dart';
import '../models/article.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // Backend health — null = checking, true = ok, false = unreachable
  bool? _backendOk;

  @override
  void initState() {
    super.initState();
    _checkBackend();
  }

  Future<void> _checkBackend() async {
    final ok = await ApiConfig.isBackendReachable();
    if (mounted) setState(() => _backendOk = ok);
  }

  // Placeholder recent articles
  final List<Map<String, String>> _recent = [
    {
      'title': 'Telugu Daily News',
      'subtitle': 'Processed 10 min ago · 3 pages',
      'category': 'News',
      'duration': '4:32',
    },
    {
      'title': 'Official Statement — AP Govt',
      'subtitle': 'Processed 2 hours ago · 1 page',
      'category': 'Government',
      'duration': '1:48',
    },
    {
      'title': 'Sakshi Editorial',
      'subtitle': 'Yesterday · 2 pages',
      'category': 'Editorial',
      'duration': '3:10',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_backendOk == false) _BackendBanner(onRetry: _checkBackend),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 1:
        return _SearchTab();
      case 2:
        return _LibraryTab();
      default:
        return _HomeTab(recent: _recent);
    }
  }

  Widget _buildBottomNav(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 0, thickness: 0.5, color: GVColors.borderTertiary(context)),
        BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: 'Search',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.library_music_outlined),
              activeIcon: Icon(Icons.library_music),
              label: 'Library',
            ),
          ],
        ),
      ],
    );
  }
}

// ── Home tab ─────────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  final List<Map<String, String>> recent;
  const _HomeTab({required this.recent});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            _buildHeroCard(context),
            const SizedBox(height: 24),
            _buildSectionLabel(context, 'Continue listening'),
            const SizedBox(height: 12),
            _buildContinueRow(context),
            const SizedBox(height: 24),
            _buildSectionLabel(context, 'Recent documents'),
            const SizedBox(height: 8),
            ...recent.map((item) => _buildArticleRow(context, item)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Text('GatiVani', style: GVTypography.title(context)),
          const Spacer(),
          _IconBtn(
            icon: Icons.notifications_none_outlined,
            onTap: () {},
          ),
          const SizedBox(width: 4),
          _IconBtn(
            icon: Icons.settings_outlined,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: GVColors.accentBg(context),
          borderRadius: BorderRadius.circular(GVRadius.lg),
          border: Border.all(
            color: GVColors.accent(context).withOpacity(0.2),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TierBadge(tier: 'Premium Advanced'),
            const SizedBox(height: 14),
            Text(
              'Scan a document,\nhear it in Telugu.',
              style: GVTypography.display(context).copyWith(
                color: GVColors.accent(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Camera, gallery, or PDF — we handle the rest.',
              style: GVTypography.bodySecondary(context),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const UploadContentScreen()),
                  );
                },
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: const Text('Start capture'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueRow(BuildContext context) {
    final items = [
      {'title': 'Telugu Daily News', 'progress': '0.6', 'duration': '4:32'},
      {'title': 'AP Govt Statement', 'progress': '0.2', 'duration': '1:48'},
      {'title': 'Sakshi Editorial', 'progress': '0.85', 'duration': '3:10'},
    ];
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final item = items[i];
          final progress = double.parse(item['progress']!);
          return _ContinueCard(
            title: item['title']!,
            duration: item['duration']!,
            progress: progress,
          );
        },
      ),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(label, style: GVTypography.heading(context)),
    );
  }

  Widget _buildArticleRow(BuildContext context, Map<String, String> item) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: GVColors.bgTertiary(context),
                borderRadius: BorderRadius.circular(GVRadius.md),
                border: Border.all(
                  color: GVColors.borderTertiary(context),
                  width: 0.5,
                ),
              ),
              child: Icon(
                Icons.article_outlined,
                size: 20,
                color: GVColors.textSecondary(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['title']!,
                      style: GVTypography.body(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(item['subtitle']!,
                      style: GVTypography.small(context)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(item['duration']!,
                    style: GVTypography.small(context)),
                const SizedBox(height: 4),
                _CategoryChip(label: item['category']!),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search tab (stub) ─────────────────────────────────────────────────────────

class _SearchTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search', style: GVTypography.title(context)),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                hintText: 'Documents, categories...',
                prefixIcon: Icon(Icons.search,
                    size: 18, color: GVColors.textTertiary(context)),
              ),
            ),
            const SizedBox(height: 24),
            Text('Browse categories', style: GVTypography.heading(context)),
            const SizedBox(height: 12),
            _CategoryGrid(),
          ],
        ),
      ),
    );
  }
}

// ── Library tab (stub) ────────────────────────────────────────────────────────

class _LibraryTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Your library', style: GVTypography.title(context)),
                const Spacer(),
                _IconBtn(
                  icon: Icons.add,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const UploadContentScreen()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  Icon(Icons.library_music_outlined,
                      size: 48, color: GVColors.textTertiary(context)),
                  const SizedBox(height: 16),
                  Text('No saved articles yet',
                      style: GVTypography.heading(context)),
                  const SizedBox(height: 8),
                  Text('Scan a document to get started',
                      style: GVTypography.bodySecondary(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Backend status banner ─────────────────────────────────────────────────────

class _BackendBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _BackendBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        color: GVColors.dangerBg(context),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 16, color: GVColors.danger(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cannot reach GatiVani server. Document processing unavailable.',
                style: TextStyle(fontSize: 12, color: GVColors.danger(context)),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Retry',
                  style: TextStyle(
                      fontSize: 12,
                      color: GVColors.danger(context),
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GVRadius.md),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 20, color: GVColors.textSecondary(context)),
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  final String tier;
  const _TierBadge({required this.tier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: GVColors.tierBg(context, tier),
        borderRadius: BorderRadius.circular(GVRadius.pill),
        border: Border.all(
          color: GVColors.tierColor(context, tier).withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        tier,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: GVColors.tierColor(context, tier),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  const _CategoryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: GVColors.bgTertiary(context),
        borderRadius: BorderRadius.circular(GVRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: GVColors.textTertiary(context),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final String title;
  final String duration;
  final double progress;
  const _ContinueCard(
      {required this.title, required this.duration, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GVColors.bgPrimary(context),
        borderRadius: BorderRadius.circular(GVRadius.lg),
        border: Border.all(
          color: GVColors.borderTertiary(context),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: GVColors.bgTertiary(context),
              borderRadius: BorderRadius.circular(GVRadius.md),
            ),
            child: Icon(Icons.article_outlined,
                size: 18, color: GVColors.textSecondary(context)),
          ),
          const Spacer(),
          Text(title,
              style: GVTypography.body(context)
                  .copyWith(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: GVColors.borderTertiary(context),
              valueColor:
                  AlwaysStoppedAnimation<Color>(GVColors.accent(context)),
            ),
          ),
          const SizedBox(height: 4),
          Text(duration, style: GVTypography.small(context)),
        ],
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  final List<Map<String, dynamic>> _categories = const [
    {'label': 'News', 'icon': Icons.newspaper_outlined},
    {'label': 'Government', 'icon': Icons.account_balance_outlined},
    {'label': 'Editorial', 'icon': Icons.edit_note_outlined},
    {'label': 'Education', 'icon': Icons.school_outlined},
    {'label': 'Health', 'icon': Icons.health_and_safety_outlined},
    {'label': 'Business', 'icon': Icons.business_center_outlined},
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.8,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, i) {
        final cat = _categories[i];
        return Container(
          decoration: BoxDecoration(
            color: GVColors.bgPrimary(context),
            borderRadius: BorderRadius.circular(GVRadius.lg),
            border: Border.all(
              color: GVColors.borderTertiary(context),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(cat['icon'] as IconData,
                  size: 18, color: GVColors.textSecondary(context)),
              const SizedBox(width: 8),
              Text(cat['label'] as String,
                  style: GVTypography.body(context).copyWith(fontSize: 14)),
            ],
          ),
        );
      },
    );
  }
}
