import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../tokens.dart';

/// Vertical scroll that gently settles at each section's top (§8).
/// Sections keep their natural heights — no page-sized gaps — and after a
/// scroll ends, if a section boundary is nearby (within ~45% of the
/// viewport) the list glides to it. Sections that contain their own
/// scrollable keep it: the inner list wins drags inside its bounds, the
/// outer scroll moves from the headers and edges around it.
class GatiSnapScroll extends StatefulWidget {
  const GatiSnapScroll({
    super.key,
    required this.sections,
    this.onRefresh,
    this.padding,
  });

  final List<Widget> sections;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry? padding;

  @override
  State<GatiSnapScroll> createState() => _GatiSnapScrollState();
}

class _GatiSnapScrollState extends State<GatiSnapScroll> {
  final _ctl = ScrollController();
  late List<GlobalKey> _keys;
  bool _snapping = false;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.sections.length, (_) => GlobalKey());
  }

  @override
  void didUpdateWidget(GatiSnapScroll old) {
    super.didUpdateWidget(old);
    if (old.sections.length != widget.sections.length) {
      _keys = List.generate(widget.sections.length, (_) => GlobalKey());
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  bool _onNotification(ScrollNotification n) {
    if (n.depth != 0) return false; // inner lists snap nothing
    if (n is ScrollEndNotification && !_snapping) _maybeSnap();
    return false;
  }

  void _maybeSnap() {
    if (!_ctl.hasClients) return;
    final pos = _ctl.position;
    final current = pos.pixels;
    double? best;
    var bestDist = double.infinity;
    for (final k in _keys) {
      final ro = k.currentContext?.findRenderObject();
      if (ro == null || !ro.attached) continue;
      final viewport = RenderAbstractViewport.maybeOf(ro);
      if (viewport == null) continue;
      final target = viewport
          .getOffsetToReveal(ro, 0.0)
          .offset
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      final d = (target - current).abs();
      if (d < bestDist) {
        bestDist = d;
        best = target;
      }
    }
    if (best == null) return;
    // Already settled, or the nearest boundary is too far to yank to.
    // 0.55 × viewport: with sections at most viewport-height, SOME boundary
    // is always within reach, so the scroll never strands between sections.
    if (bestDist < 2 || bestDist > pos.viewportDimension * 0.55) return;
    _snapping = true;
    _ctl
        .animateTo(best,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic)
        .whenComplete(() => _snapping = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget list = ListView(
      controller: _ctl,
      padding: widget.padding,
      children: [
        for (var i = 0; i < widget.sections.length; i++)
          KeyedSubtree(key: _keys[i], child: widget.sections[i]),
      ],
    );
    if (widget.onRefresh != null) {
      list = RefreshIndicator(
          onRefresh: widget.onRefresh!, color: kAccent, child: list);
    }
    return NotificationListener<ScrollNotification>(
        onNotification: _onNotification, child: list);
  }
}
