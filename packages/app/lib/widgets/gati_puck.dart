import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/tokens.dart';
import '../services/playback_service.dart';

/// The playback puck — the mini-player shrunk to a floating, draggable
/// bubble so phones keep their screen. Visible whenever anything is
/// playing/loading (audio is NEVER allowed without a visible handle):
///
///   • gold progress ring shows position at a glance
///   • center tap = play/pause (retry when errored)
///   • the small chevron badge opens the full player
///   • drag to move — it snaps to the nearest edge and remembers its spot
///   • while dragging, a ✕ zone appears at the bottom: drop the puck on
///     it to stop playback entirely (which also aborts mid-synthesis)
///
/// Place as a direct child of a Stack that fills the screen area.
class GatiPuck extends StatefulWidget {
  const GatiPuck({super.key});

  @override
  State<GatiPuck> createState() => _GatiPuckState();
}

class _GatiPuckState extends State<GatiPuck> {
  static const _size = 56.0;
  // Session memory: where the user parked it, shared across screens.
  static Offset? _saved;

  Offset? _pos;
  bool _dragging = false;
  bool _overStop = false;
  String? _lastError;

  // Anchors captured on pointer-down, so drag position is computed as an
  // absolute offset from the pointer's total movement rather than summed
  // deltas — avoids any lag/catch-up jump once _dragThreshold is crossed.
  Offset? _pointerDownGlobal;
  Offset? _pointerDownPuck;
  double _moveAccum = 0;
  // Small enough to feel instant, big enough to keep finger jitter during a
  // tap from being misread as a drag. A GestureDetector's onPan* here would
  // instead compete with the ring/badge's onTap in the same gesture arena,
  // which needs ~18px of movement before it resolves in favor of the drag —
  // that resolution delay is what made the puck feel like it needed a
  // deliberate wind-up before it would move.
  static const _dragThreshold = 6.0;

  void _snapToEdge(Size area) {
    final p = _pos;
    if (p == null) return;
    final targetX =
        (p.dx + _size / 2) < area.width / 2 ? 12.0 : area.width - _size - 12.0;
    setState(() => _pos = Offset(targetX, p.dy));
    _saved = _pos;
  }

  Offset _clamp(Offset p, Size area) => Offset(
        p.dx.clamp(8.0, area.width - _size - 8.0),
        p.dy.clamp(8.0, area.height - _size - 8.0),
      );

  bool _inStopZone(Offset p, Size area) {
    final puckCenter = p + const Offset(_size / 2, _size / 2);
    final stopCenter = Offset(area.width / 2, area.height - 44);
    return (puckCenter - stopCenter).distance < 52;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(builder: (context, cons) {
        final area = Size(cons.maxWidth, cons.maxHeight);
        return ListenableBuilder(
          listenable: PlaybackService.i,
          builder: (context, _) {
            final ps = PlaybackService.i;
            final a = ps.current;
            if (a == null) {
              _lastError = null;
              return const SizedBox.shrink();
            }
            _lastError = ps.error;
            final pos = _clamp(
                _pos ?? _saved ?? Offset(12, area.height - _size - 90), area);
            _pos = pos;
            final durMs = ps.duration.inMilliseconds;
            final frac = durMs == 0
                ? 0.0
                : (ps.position.inMilliseconds / durMs).clamp(0.0, 1.0);
            final errored = ps.error != null && !ps.loading;
            return Stack(children: [
              // Drop-to-stop target, only while dragging.
              if (_dragging)
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _overStop ? Gati.kumkuma : Gati.kumkumaSoft,
                        shape: BoxShape.circle,
                        boxShadow: Gati.shadow,
                      ),
                      child: Icon(Icons.close_rounded,
                          size: 22,
                          color:
                              _overStop ? Colors.white : Gati.kumkumaDeep),
                    ),
                  ),
                ),
              Positioned(
                left: pos.dx,
                top: pos.dy,
                child: Listener(
                  onPointerDown: (e) {
                    _pointerDownGlobal = e.position;
                    _pointerDownPuck = _pos ?? pos;
                    _moveAccum = 0;
                  },
                  // A plain Listener never enters the gesture arena, so it
                  // can't compete with the ring/badge's onTap below — taps
                  // resolve immediately on release with no drag recognizer
                  // waiting to see if it should win instead. That's what
                  // lets a tap stay a tap while any real movement, from the
                  // very first pixel past _dragThreshold, moves the puck.
                  onPointerMove: (e) {
                    final downGlobal = _pointerDownGlobal;
                    final downPuck = _pointerDownPuck;
                    if (downGlobal == null || downPuck == null) return;
                    _moveAccum += e.delta.distance;
                    if (!_dragging && _moveAccum < _dragThreshold) return;
                    final next =
                        _clamp(downPuck + (e.position - downGlobal), area);
                    setState(() {
                      _dragging = true;
                      _pos = next;
                      _overStop = _inStopZone(next, area);
                    });
                  },
                  onPointerUp: (_) {
                    _pointerDownGlobal = null;
                    _pointerDownPuck = null;
                    if (!_dragging) return;
                    final stop = _overStop;
                    setState(() {
                      _dragging = false;
                      _overStop = false;
                    });
                    if (stop) {
                      PlaybackService.i.stop();
                    } else {
                      _snapToEdge(area);
                    }
                  },
                  onPointerCancel: (_) {
                    _pointerDownGlobal = null;
                    _pointerDownPuck = null;
                    setState(() {
                      _dragging = false;
                      _overStop = false;
                    });
                  },
                  child: _puck(ps, frac, errored),
                ),
              ),
            ]);
          },
        );
      }),
    );
  }

  Widget _puck(PlaybackService ps, double frac, bool errored) {
    return SizedBox(
      width: _size + 10,
      height: _size + 10,
      child: Stack(clipBehavior: Clip.none, children: [
        // Ring + body: tap toggles playback (or retries after an error).
        GestureDetector(
          onTap: errored ? ps.retry : ps.toggle,
          child: CustomPaint(
            painter: _RingPainter(
                frac: frac, color: errored ? Gati.kumkuma : Gati.pasupu),
            child: Container(
              width: _size,
              height: _size,
              padding: const EdgeInsets.all(5),
              child: Container(
                decoration: const BoxDecoration(
                    color: Gati.inkDeep, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: ps.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Gati.pasupu))
                    : Icon(
                        errored
                            ? Icons.refresh_rounded
                            : ps.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                        color: errored ? Gati.kumkuma : Gati.pasupu,
                        size: 24),
              ),
            ),
          ),
        ),
        // Shoulder badge → full player.
        Positioned(
          top: -2,
          right: -2,
          child: GestureDetector(
            onTap: () => context.push('/player'),
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Gati.paper,
                shape: BoxShape.circle,
                border: Border.all(color: Gati.line, width: 0.5),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 4,
                      offset: Offset(0, 1)),
                ],
              ),
              child: const Icon(Icons.expand_less_rounded,
                  size: 16, color: Gati.ink),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.frac, required this.color});
  final double frac;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(_GatiPuckState._size / 2, _GatiPuckState._size / 2);
    const radius = _GatiPuckState._size / 2 - 1.5;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Gati.ink.withValues(alpha: 0.18);
    final prog = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(center, radius, track);
    if (frac > 0) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          -math.pi / 2, 2 * math.pi * frac, false, prog);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.frac != frac || old.color != color;
}
