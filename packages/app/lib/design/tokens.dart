import 'package:flutter/material.dart';

/// GatiVani design tokens — the single source of truth for the reimagined
/// (Today / player / mini-player) surfaces.
///
/// Rule (Anthropic-structure): UI code must reference these, never raw hex.
/// Values (Apple-craft): one warm-paper brand, one terracotta accent, two text
/// weights only (400 / 500), a small spacing scale, soft radii.
class Gati {
  Gati._();

  // ── Palette ────────────────────────────────────────────────────────────
  static const ink = Color(0xFF2C2C2A); // near-black, primary text + dark cards
  static const paper = Color(0xFFFAF7F0); // warm ivory page background
  static const accent = Color(0xFFD85A30); // terracotta — the one accent
  static const accentSoft = Color(0xFFFAECE7); // accent tint (chips, badges)
  static const accentText = Color(0xFF993C1D); // text on accentSoft
  static const muted = Color(0xFF888780); // secondary text
  static const line = Color(0xFFE7E4DB); // hairline borders on paper

  // On-ink (text/elements inside dark cards + player)
  static const onInk = Color(0xFFFAF7F0); // primary text on ink
  static const onInkMuted = Color(0xFFB4B2A9); // secondary text on ink
  static const onInkTrack = Color(0xFF5F5E5A); // inactive progress track on ink
  static const onInkPast = Color(0xFF8A8884); // played/dimmed lyrics
  static const onInkFuture = Color(0xFFCFCDC5); // upcoming lyrics

  // ── Spacing scale (px) ─────────────────────────────────────────────────
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;

  // ── Radii ──────────────────────────────────────────────────────────────
  static const rCard = 16.0;
  static const rChip = 14.0;
  static const rPill = 24.0;

  // ── Motion ─────────────────────────────────────────────────────────────
  static const dur = Duration(milliseconds: 300);
}

// Backward-compatible short names used across the reimagined screens.
// These remain the LIGHT values; for theme-aware surfaces resolve a
// [GatiPalette] from context instead. kAccent (terracotta) is shared by both
// modes, so it stays a plain const.
const kInk = Gati.ink;
const kPaper = Gati.paper;
const kAccent = Gati.accent;
const kMuted = Gati.muted;

/// Warm-dark counterpart to the paper palette. Keeps the brand warm (no cold
/// blue-greys) so dark mode still feels like the same product.
class GatiDark {
  GatiDark._();
  static const paper = Color(0xFF1A1916); // warm near-black page bg
  static const ink = Color(0xFFECE7DD); // warm off-white primary text
  static const muted = Color(0xFF9C968A); // secondary text
  static const surface = Color(0xFF26241F); // cards / tiles on the dark bg
  static const line = Color(0xFF38342C); // hairline borders
  static const chip = Color(0xFF2E2B24); // segmented-control / chip background
}

/// Brightness-resolved surface colors for the reimagined screens. Resolve once
/// per build: `final p = GatiPalette.of(context);` then use `p.paper`, `p.ink`…
class GatiPalette {
  const GatiPalette(
      {required this.dark,
      required this.paper,
      required this.ink,
      required this.muted,
      required this.surface,
      required this.line,
      required this.chip});

  final bool dark;
  final Color paper, ink, muted, surface, line, chip;

  static const _light = GatiPalette(
    dark: false,
    paper: Gati.paper,
    ink: Gati.ink,
    muted: Gati.muted,
    surface: Colors.white,
    line: Gati.line,
    chip: Color(0xFFEFE9DE),
  );
  static const _dark = GatiPalette(
    dark: true,
    paper: GatiDark.paper,
    ink: GatiDark.ink,
    muted: GatiDark.muted,
    surface: GatiDark.surface,
    line: GatiDark.line,
    chip: GatiDark.chip,
  );

  static GatiPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;
}
