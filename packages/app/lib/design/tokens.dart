import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// GatiVāni design tokens — the single source of truth for all surfaces.
/// Spec: docs/DESIGN_SYSTEM.md (§4 color, §5 type, §7 motion).
///
/// Rule: UI code must reference these, never raw hex.
class Gati {
  Gati._();

  // ── Neutrals ──────────────────────────────────────────────────────────
  static const ink = Color(0xFF2C2C2A); // near-black, primary text + dark cards
  static const inkDeep = Color(0xFF0E0D0B); // player / immersive surfaces
  static const paper = Color(0xFFFAF7F0); // warm ivory page background
  static const muted = Color(0xFF888780); // secondary text
  static const line = Color(0xFFE7E4DB); // hairline borders on paper
  static const band = Color(0xFFFFFFFF); // masthead + tab bar chrome

  // ── Brand accents — Pasupu (the voice) & Kumkuma (live) ───────────────
  // Gold marks what speaks or plays; vermilion is reserved for live/breaking
  // and destructive actions, so red never wolf-cries.
  static const pasupu = Color(0xFFE39A0B); // fills & large icons on ink
  static const pasupuDeep = Color(0xFF9A6200); // text & icons on paper (AA)
  static const pasupuSoft = Color(0xFFFBEFD6); // tint backgrounds on paper
  static const pasupuGlow = Color(0xFFF4B942); // hover / active on ink
  static const kumkuma = Color(0xFFD3402E); // LIVE dot, breaking, destructive
  static const kumkumaDeep = Color(0xFF8F1F13); // live/destructive text on paper
  static const kumkumaSoft = Color(0xFFFBE7E3); // live/danger tints on paper

  // Back-compat accent roles (were terracotta). Existing callers sit on
  // paper surfaces, so the on-paper gold stop is the safe default; on-ink
  // surfaces should use [pasupu]/[pasupuGlow] directly.
  static const accent = pasupuDeep;
  static const accentSoft = pasupuSoft;
  static const accentText = pasupuDeep;

  // ── Semantic ───────────────────────────────────────────────────────────
  static const success = Color(0xFF0F6E56); // on paper
  static const successBright = Color(0xFF1D9E75); // on ink / dark surfaces

  // On-ink (text/elements inside dark cards + player)
  static const onInk = Color(0xFFFAF7F0); // primary text on ink
  static const onInkMuted = Color(0xFFB4B2A9); // secondary text on ink
  static const onInkTrack = Color(0xFF5F5E5A); // inactive progress track on ink
  static const onInkPast = Color(0xFF8A8884); // played/dimmed lyrics
  static const onInkFuture = Color(0xFFCFCDC5); // upcoming lyrics
  static const inkChip = Color(0xFF35322B); // chips / inactive fills on ink
  static const pasupuTint = Color(0x24E39A0B); // active-row wash on ink

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

  // ── Elevation — the one shadow, floating layers only ───────────────────
  static const shadow = [
    BoxShadow(offset: Offset(0, 8), blurRadius: 24, color: Color(0x240E0D0B)),
  ];

  // ── Motion — deprecated alias, use [GatiMotion] ────────────────────────
  static const dur = GatiMotion.madhyama;
}

/// Motion tempos (§7) — named after Carnatic laya, because gati is the brand.
class GatiMotion {
  GatiMotion._();
  static const druta = Duration(milliseconds: 120); // press feedback, toggles
  static const madhyama = Duration(milliseconds: 240); // fades, list changes
  static const vilamba = Duration(milliseconds: 360); // sheets, player rise
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const move = Curves.easeInOutCubic;
}

/// Per-script type scale (§5). Anek Telugu carries display + UI in both
/// scripts; Noto Serif carries long-form reading. Telugu takes taller
/// line-heights (stacked vowel signs and conjuncts) — encoded here, not
/// left to individual screens.
class GatiType {
  GatiType._();

  static bool _te(String lang) => lang == 'te';

  /// Script of actual content — articles may be Telugu while the UI language
  /// is English. Reading surfaces size by this; UI chrome uses settings lang.
  static String scriptOf(String text) =>
      RegExp(r'[ఀ-౿]').hasMatch(text) ? 'te' : 'en';

  static TextStyle _anek(
          String lang, double size, double latinH, double teluguH,
          FontWeight w) =>
      GoogleFonts.anekTelugu(
          fontSize: size,
          height: (_te(lang) ? teluguH : latinH) / size,
          fontWeight: w);

  static TextStyle display(String lang) =>
      _anek(lang, 32, 38, 46, FontWeight.w600);
  static TextStyle headline(String lang) =>
      _anek(lang, 24, 30, 36, FontWeight.w600);
  static TextStyle title(String lang) =>
      _anek(lang, 18, 24, 27, FontWeight.w500);
  static TextStyle bodyUi(String lang) =>
      _anek(lang, 15, 21, 23, FontWeight.w400);
  static TextStyle label(String lang) =>
      _anek(lang, 13, 16, 19, FontWeight.w500);
  static TextStyle caption(String lang) =>
      _anek(lang, 12, 16, 17, FontWeight.w400);
  static TextStyle lyrics(String lang) =>
      _anek(lang, 22, 32, 35, FontWeight.w500);

  static TextStyle bodyRead(String lang) => _te(lang)
      ? GoogleFonts.notoSerifTelugu(fontSize: 18, height: 31 / 18)
      : GoogleFonts.notoSerif(fontSize: 17, height: 26 / 17);
}

// Backward-compatible short names used across the reimagined screens.
// These remain the LIGHT values; for theme-aware surfaces resolve a
// [GatiPalette] from context instead. kAccent (pasupu deep) is shared by
// both modes, so it stays a plain const.
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
  static const band = Color(0xFF211E19); // masthead + tab bar chrome
  static const accentSoft = Color(0xFF3A2C08); // pasupu tint on dark surfaces
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
