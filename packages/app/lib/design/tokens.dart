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
const kInk = Gati.ink;
const kPaper = Gati.paper;
const kAccent = Gati.accent;
const kMuted = Gati.muted;
