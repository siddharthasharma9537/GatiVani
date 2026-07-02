import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/tokens.dart';
import '../design/section_colors.dart';
import '../l10n/strings.dart';
import '../models/newspaper_article.dart';
import '../services/settings_provider.dart';

/// An article row as a soft card tinted in its section's color, so a list of
/// them carries the same editorial palette as the section tiles. Tapping the
/// card opens the full player; tapping the ▶ plays it in the mini-player.
class ArticleCard extends StatelessWidget {
  const ArticleCard(
      {super.key,
      required this.article,
      required this.onOpen,
      required this.onPlay,
      this.onLongPress,
      this.selectionMode = false,
      this.selected = false,
      this.onToggleSelect});
  final NewspaperArticle article;
  final VoidCallback onOpen;
  final VoidCallback onPlay;
  // Long-press → options sheet (play next, queue, save, download).
  final VoidCallback? onLongPress;
  // Multi-select mode: tapping the card toggles selection; the ▶ becomes a tick.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().lang;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = sectionRamp(article.category, dark: dark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: r[0],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected
                  ? Gati.successBright
                  : r[1].withValues(alpha: 0.07),
              width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: selectionMode ? onToggleSelect : onOpen,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                              color: r[1])),
                      const SizedBox(height: 4),
                      Text(
                          '${sectionLabel(article.category, lang)} · '
                          'p${article.page} · '
                          '${(article.estimatedDurationSeconds / 60).ceil()} min',
                          style: TextStyle(fontSize: 12, color: r[2])),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (selectionMode)
                  // Selection tick: green check when selected, empty ring else.
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? Gati.successBright
                          : Colors.transparent,
                      border: Border.all(
                          color: selected
                              ? Gati.successBright
                              : r[2],
                          width: 1.5),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 18)
                        : null,
                  )
                else
                  GestureDetector(
                    onTap: onPlay,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                          color: kAccent, shape: BoxShape.circle),
                      child:
                          const Icon(Icons.play_arrow, color: kPaper, size: 20),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
