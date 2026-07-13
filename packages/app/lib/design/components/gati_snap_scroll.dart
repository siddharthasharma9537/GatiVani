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
  // Targets sit 12px SHY of flush — a flush reveal planted section tops
  // (and the first card) right against the chrome above.
  static const _snapInset = 12.0;

  List<double> _offsets() {
    final out = <double>[];
    for (final k in _keys) {
      final ro = k.currentContext?.findRenderObject();
      if (ro == null || !ro.attached) continue;
      final viewport = RenderAbstractViewport.maybeOf(ro);
      if (viewport == null) continue;
      out.add(viewport.getOffsetToReveal(ro, 0.0).offset - _snapInset);
    }
    out.sort();
    return out;
  }

  // ── Inner-list edge handoff ────────────────────────────────────────────
  // Nested scrollables don't chain in Flutter: an inner list (Latest
  // stories / All articles) that hits its top or bottom just stops, and the
  // page beyond it is unreachable without moving to the gutter. So when an
  // inner list overscrolls, the remainder drives THIS outer scroll — the
  // drag keeps following the finger across the boundary, and on release the
  // page glides one section in that direction and settles.
  double _handoffDelta = 0; // signed accumulated inner-overscroll this drag
  bool _settling = false; // an edge-handoff settle animation is running

  void _settleTo(double target) {
    final pos = _ctl.position;
    target = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - _ctl.offset).abs() < 1) return;
    _settling = true;
    _ctl
        .animateTo(target,
            duration: GatiMotion.vilamba, curve: Curves.easeOutCubic)
        .whenComplete(() => _settling = false);
  }

  // The next section header in [direction] (+1 down / −1 up), or null when
  // there is none (already at the outermost section).
  double? _headerBeyond(int direction) {
    final pos = _ctl.position;
    final offs = _offsets()
        .map((o) => o.clamp(pos.minScrollExtent, pos.maxScrollExtent))
        .toList();
    final px = _ctl.offset;
    if (direction > 0) {
      for (final o in offs) {
        if (o > px + 4) return o;
      }
    } else {
      for (final o in offs.reversed) {
        if (o < px - 4) return o;
      }
    }
    return null;
  }

  bool _onInnerScroll(ScrollNotification n) {
    if (n.depth == 0 || _settling) return false;
    if (n.metrics.axis != Axis.vertical) return false;

    if (n is OverscrollNotification) {
      if (n.dragDetails != null) {
        // Finger still down past the inner edge → the page follows it 1:1.
        final pos = _ctl.position;
        _handoffDelta += n.overscroll;
        pos.jumpTo((_ctl.offset + n.overscroll)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent));
      } else if (n.velocity.abs() > 60) {
        // Fling remainder crossing the edge → glide one section over.
        final t = _headerBeyond(n.velocity > 0 ? 1 : -1);
        if (t != null) _settleTo(t);
        _handoffDelta = 0;
      }
      return false;
    }

    if (n is ScrollEndNotification && _handoffDelta.abs() > 12) {
      // Drag-driven handoff released → settle on the section in the drag's
      // direction (falling back to the nearest header, so a hesitant pull
      // never strands the page between sections).
      final dir = _handoffDelta > 0 ? 1 : -1;
      final t = _headerBeyond(dir);
      if (t != null) {
        _settleTo(t);
      } else {
        final pos = _ctl.position;
        final offs = _offsets()
            .map((o) => o.clamp(pos.minScrollExtent, pos.maxScrollExtent))
            .toList();
        if (offs.isNotEmpty) {
          final px = _ctl.offset;
          _settleTo(offs
              .reduce((a, b) => (a - px).abs() <= (b - px).abs() ? a : b));
        }
      }
      _handoffDelta = 0;
    }
    return false;
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
    // Clamping physics for every descendant list: the edge handoff rides on
    // OverscrollNotification, which bouncing physics (iOS-flavored
    // platforms) never emits — the inner list would rubber-band instead of
    // handing the drag to the page.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(physics: const ClampingScrollPhysics()),
      child: NotificationListener<ScrollNotification>(
          onNotification: _onInnerScroll, child: list),
    );
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
    if (velocity.abs() > 60) {
      // iOS-style proximity snap: let the fling decelerate NATURALLY and
      // settle on the header nearest to where it would have landed — a
      // gentle flick travels one section, a hard fling several. (The old
      // rule teleported to the immediate next header at ANY velocity,
      // which read as a magnet yanking the page.)
      final natural = super.createBallisticSimulation(position, velocity);
      final end = (natural?.x(5.0) ?? px)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      target =
          offs.reduce((a, b) => (a - end).abs() <= (b - end).abs() ? a : b);
      // Never settle AGAINST the fling's direction (a short fling whose
      // natural end is nearest its own starting header used to snap
      // backwards — the jitter tug-of-war). Advance at least one header.
      if (velocity > 0 && target <= px + 4) {
        target = offs.firstWhere((o) => o > px + 4,
            orElse: () => position.maxScrollExtent);
      } else if (velocity < 0 && target >= px - 4) {
        target = offs.lastWhere((o) => o < px - 4,
            orElse: () => position.minScrollExtent);
      }
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
    // no wobble. Softer than the original (m .5/k 180): that spring closed
    // in ~150ms and felt like a magnet grabbing the page.
    return ScrollSpringSimulation(
      SpringDescription.withDampingRatio(
          mass: 0.8, stiffness: 95, ratio: 1.0),
      px,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }
}
