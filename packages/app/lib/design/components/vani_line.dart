import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// The brand's signature voice line (docs/DESIGN_SYSTEM.md §3.3).
///
/// Flat when silent; a travelling sine wave while speaking; a single
/// travelling pulse when live; a sweeping shimmer while loading. Honors
/// `MediaQuery.disableAnimations` by freezing flat.
enum VaniLineMode { flat, wave, live, loading }

class VaniLine extends StatefulWidget {
  const VaniLine({
    super.key,
    this.mode = VaniLineMode.flat,
    this.color = Gati.pasupu,
    this.pulseColor = Gati.kumkuma,
    this.strokeWidth = 2,
    this.cycles = 3.5,
    this.height,
  });

  final VaniLineMode mode;
  final Color color;

  /// Live-pulse color; ignored by the other modes.
  final Color pulseColor;
  final double strokeWidth;

  /// Visible wave cycles across the full width (spec: 3–4).
  final double cycles;

  /// Defaults to 8× stroke — enough headroom for the 3×-stroke amplitude.
  final double? height;

  @override
  State<VaniLine> createState() => _VaniLineState();
}

class _VaniLineState extends State<VaniLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: _period(widget.mode));

  static Duration _period(VaniLineMode m) => switch (m) {
        VaniLineMode.live => const Duration(milliseconds: 2400),
        VaniLineMode.loading => const Duration(milliseconds: 1800),
        _ => const Duration(milliseconds: 1600),
      };

  void _sync(bool reduced) {
    final animate = !reduced && widget.mode != VaniLineMode.flat;
    _c.duration = _period(widget.mode);
    if (animate) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    _sync(reduced);
    final h = widget.height ?? widget.strokeWidth * 8;
    // The wave's amplitude eases in/out on mode changes so speech starting
    // and stopping reads as the line waking up, not a hard swap.
    final wantWave = !reduced && widget.mode == VaniLineMode.wave;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: wantWave ? 1 : 0),
      duration: GatiMotion.madhyama,
      curve: Curves.easeInOut,
      builder: (context, amp, _) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => SizedBox(
          height: h,
          width: double.infinity,
          child: CustomPaint(
            painter: _VaniPainter(
              mode: widget.mode,
              t: _c.value,
              amp: amp,
              color: widget.color,
              pulseColor: widget.pulseColor,
              stroke: widget.strokeWidth,
              cycles: widget.cycles,
            ),
          ),
        ),
      ),
    );
  }
}

class _VaniPainter extends CustomPainter {
  _VaniPainter({
    required this.mode,
    required this.t,
    required this.amp,
    required this.color,
    required this.pulseColor,
    required this.stroke,
    required this.cycles,
  });

  final VaniLineMode mode;
  final double t; // 0→1 repeating phase
  final double amp; // eased 0→1 wave amplitude factor
  final Color color;
  final Color pulseColor;
  final double stroke;
  final double cycles;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final w = size.width;
    final line = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    switch (mode) {
      case VaniLineMode.live:
        canvas.drawLine(Offset(0, cy), Offset(w, cy), line);
        // One pulse travels the line per period, fading at the edges.
        final px = t * w;
        final fade = math.sin(math.pi * t).clamp(0.0, 1.0);
        canvas.drawCircle(
            Offset(px, cy),
            stroke * 1.9,
            Paint()
              ..color = pulseColor
                  .withValues(alpha: pulseColor.a * fade));
      case VaniLineMode.loading:
        canvas.drawLine(
            Offset(0, cy),
            Offset(w, cy),
            Paint()
              ..color = color.withValues(alpha: color.a * 0.3)
              ..strokeWidth = stroke
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke);
        // Bright segment sweeping left→right.
        final seg = w * 0.28;
        final x0 = (w + seg) * t - seg;
        canvas.drawLine(Offset(x0.clamp(0, w), cy),
            Offset((x0 + seg).clamp(0, w), cy), line);
      case VaniLineMode.flat:
      case VaniLineMode.wave:
        final a = 3 * stroke * amp;
        if (a < 0.05) {
          canvas.drawLine(Offset(0, cy), Offset(w, cy), line);
          return;
        }
        final path = Path()..moveTo(0, cy + a * math.sin(-2 * math.pi * t));
        final steps = math.max(16, (w / 3).round());
        for (var i = 1; i <= steps; i++) {
          final x = w * i / steps;
          final y = cy +
              a * math.sin(2 * math.pi * (cycles * i / steps - t));
          path.lineTo(x, y);
        }
        canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_VaniPainter old) =>
      old.t != t ||
      old.amp != amp ||
      old.mode != mode ||
      old.color != color ||
      old.stroke != stroke;
}
