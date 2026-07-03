import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../tokens.dart';

/// Vertical scroll that stops at each section's header (§8).
///
/// Real snap physics, not an after-the-fact correction: a fling's ballistic
/// simulation is retargeted to the NEXT section boundary in the fling's
/// direction, so the scroll decelerates and comes to rest exactly on a
/// section header — one section per fling. Slow drags settle to the nearest
/// boundary. Sections keep natural heights (no page gaps), and sections
/// containing their own scrollable keep it: the inner list wins drags
/// inside its bounds.
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

  // Section-top offsets, measured from the live render tree at fling time.
  List<double> _offsets() {
    final out = <double>[];
    for (final k in _keys) {
      final ro = k.currentContext?.findRenderObject();
      if (ro == null || !ro.attached) continue;
      final viewport = RenderAbstractViewport.maybeOf(ro);
      if (viewport == null) continue;
      out.add(viewport.getOffsetToReveal(ro, 0.0).offset);
    }
    out.sort();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    Widget list = ListView(
      controller: _ctl,
      physics: _SectionSnapPhysics(offsets: _offsets),
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
    return list;
  }
}

class _SectionSnapPhysics extends ScrollPhysics {
  const _SectionSnapPhysics({required this.offsets, super.parent});

  final List<double> Function() offsets;

  @override
  _SectionSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _SectionSnapPhysics(offsets: offsets, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // Overscrolled → let the parent spring handle it normally.
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final offs = offsets()
        .map((o) =>
            o.clamp(position.minScrollExtent, position.maxScrollExtent))
        .toList();
    if (offs.isEmpty) return super.createBallisticSimulation(position, velocity);

    final px = position.pixels;
    double target;
    // ANY directional motion advances to the next header — a higher
    // threshold made gentle flings snap BACK to the previous section
    // (a jittery tug-of-war around the middle of a section).
    if (velocity > 60) {
      target = offs.firstWhere((o) => o > px + 4,
          orElse: () => position.maxScrollExtent);
    } else if (velocity < -60) {
      target = offs.lastWhere((o) => o < px - 4,
          orElse: () => position.minScrollExtent);
    } else {
      // Still release → settle on the nearest header.
      target = offs.reduce(
          (a, b) => (a - px).abs() <= (b - px).abs() ? a : b);
      if ((target - px).abs() > position.viewportDimension * 0.9) {
        return super.createBallisticSimulation(position, velocity);
      }
    }
    if ((target - px).abs() < 1) return null;
    // Critically damped: glides to the header and stops — no overshoot,
    // no wobble.
    return ScrollSpringSimulation(
      SpringDescription.withDampingRatio(
          mass: 0.5, stiffness: 180, ratio: 1.0),
      px,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }
}
