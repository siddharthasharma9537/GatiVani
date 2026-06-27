import 'package:flutter/material.dart';

// Muted, equal-lightness section tints — editorial, not rainbow. Each section
// gets its own hue for recognition; all share the same lightness so a grid or
// list of them reads as one cohesive set. [background, title, subtitle].
const Map<String, List<Color>> kSectionColors = {
  'State': [Color(0xFFE6F1FB), Color(0xFF042C53), Color(0xFF185FA5)],
  'National': [Color(0xFFFAECE7), Color(0xFF4A1B0C), Color(0xFF993C1D)],
  'International': [Color(0xFFE1F5EE), Color(0xFF04342C), Color(0xFF0F6E56)],
  'District': [Color(0xFFEAF3DE), Color(0xFF173404), Color(0xFF3B6D11)],
  'Politics': [Color(0xFFEEEDFE), Color(0xFF26215C), Color(0xFF534AB7)],
  'Editorial': [Color(0xFFF1EFE8), Color(0xFF2C2C2A), Color(0xFF5F5E5A)],
  'Opinion': [Color(0xFFFBF0E2), Color(0xFF3A2A0A), Color(0xFF7A5A18)],
  'Judiciary': [Color(0xFFFBEAF0), Color(0xFF4B1528), Color(0xFF993556)],
  'Crime': [Color(0xFFFCEBEB), Color(0xFF501313), Color(0xFFA32D2D)],
  'Business': [Color(0xFFFAEEDA), Color(0xFF412402), Color(0xFF854F0B)],
  'Sports': [Color(0xFFFBEAF0), Color(0xFF4B1528), Color(0xFF993556)],
  'Health': [Color(0xFFE1F5EE), Color(0xFF04342C), Color(0xFF0F6E56)],
  'Sci-Tech': [Color(0xFFE6F1FB), Color(0xFF042C53), Color(0xFF185FA5)],
  'Education': [Color(0xFFFAEEDA), Color(0xFF412402), Color(0xFF854F0B)],
  'Agriculture': [Color(0xFFEAF3DE), Color(0xFF173404), Color(0xFF3B6D11)],
  'Entertainment': [Color(0xFFFBEAF0), Color(0xFF4B1528), Color(0xFF993556)],
  'Devotional': [Color(0xFFFAECE7), Color(0xFF4A1B0C), Color(0xFF993C1D)],
  'Trending': [Color(0xFFFAEEDA), Color(0xFF412402), Color(0xFF854F0B)],
  'News': [Color(0xFFF1EFE8), Color(0xFF2C2C2A), Color(0xFF5F5E5A)],
};

const List<Color> _kSectionFallback = [
  Color(0xFFF1EFE8),
  Color(0xFF2C2C2A),
  Color(0xFF5F5E5A),
];

/// [background, title, subtitle] colors for a section, with a neutral gray
/// fallback so unknown/odd sections degrade gracefully. In dark mode the light
/// pastel fill would glare, so tiles/cards become a shared warm-dark surface
/// with light text and the section's pastel reused as a subtle accent — that
/// keeps per-section color recognition without lighting up the screen.
List<Color> sectionRamp(String section, {bool dark = false}) {
  final base = kSectionColors[section] ?? _kSectionFallback;
  if (!dark) return base;
  return [const Color(0xFF26241F), const Color(0xFFECE7DD), base[0]];
}
