import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/playback_service.dart';
import '../tokens.dart';
import 'vani_line.dart';

/// The GatiVāni wordmark (docs/DESIGN_SYSTEM.md §3.1).
///
/// Typeset in Anek Telugu 600; the macron over the ā is NOT the font's
/// glyph — it is the brand's voice line, drawn in gold, flat when the app
/// is silent and waving while audio plays anywhere. Telugu lockup గతివాణి
/// when [lang] is 'te'; both lockups are equal citizens.
///
/// Below 18px the macron stays static (too small to read motion).
class GatiWordmark extends StatelessWidget {
  const GatiWordmark({
    super.key,
    this.size = 24,
    this.color = Gati.ink,
    this.macronColor,
    this.lang = 'en',
    this.animated = true,
  });

  /// Font size of the letterforms.
  final double size;
  final Color color;

  /// Defaults to bright pasupu on dark letterforms' inverse — i.e. picks
  /// the gold stop that reads against the surface implied by [color].
  final Color? macronColor;
  final String lang;

  /// Set false for purely static contexts (e.g. inside pastel art cards).
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final te = lang == 'te';
    final style = GoogleFonts.anekTelugu(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.15);
    // Light letterforms mean an ink surface → bright gold; dark letterforms
    // mean a paper surface → deep gold (§4.3 contrast rule).
    final gold = macronColor ??
        (color.computeLuminance() > 0.5 ? Gati.pasupu : Gati.pasupuDeep);
    final canAnimate = animated && size >= 18;

    Widget mark(VaniLineMode mode) {
      // Measure the carrier glyph so the macron hugs it exactly — sizing by
      // font-size fractions made it bleed over the neighbouring letters.
      final carrier = te ? 'వా' : 'a';
      final tp = TextPainter(
          text: TextSpan(text: carrier, style: style),
          textDirection: TextDirection.ltr)
        ..layout();
      final macronW = tp.width * 0.94;
      final letter = Stack(
        clipBehavior: Clip.none,
        children: [
          Text(carrier, style: style),
          Positioned(
            left: (tp.width - macronW) / 2,
            top: te ? -size * 0.04 : size * 0.10,
            child: SizedBox(
              width: macronW,
              child: VaniLine(
                mode: mode,
                color: gold,
                strokeWidth: size * 0.075,
                cycles: 2,
                height: size * 0.16,
              ),
            ),
          ),
        ],
      );
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text(te ? 'గతి' : 'GatiV', style: style),
        letter,
        Text(te ? 'ణి' : 'ni', style: style),
      ]);
    }

    if (!canAnimate) return mark(VaniLineMode.flat);
    return ListenableBuilder(
      listenable: PlaybackService.i,
      builder: (context, _) => mark(PlaybackService.i.isPlaying
          ? VaniLineMode.wave
          : VaniLineMode.flat),
    );
  }
}
