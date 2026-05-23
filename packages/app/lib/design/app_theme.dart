import 'package:flutter/material.dart';

/// GatiVani design system — Claude-aligned
/// Flat, adaptive light/dark, no gradients, no glow
/// All colors are semantic and map to context, not decoration

class GVColors {
  GVColors._();

  // --- Backgrounds ---
  static Color bgPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1A1A18)
          : const Color(0xFFFFFFFF);

  static Color bgSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF252523)
          : const Color(0xFFF5F4F0);

  static Color bgTertiary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2E2E2C)
          : const Color(0xFFECEBE6);

  // --- Text ---
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFEFEEE8)
          : const Color(0xFF1A1A18);

  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF8A8A83)
          : const Color(0xFF5F5E5A);

  static Color textTertiary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF555550)
          : const Color(0xFF888780);

  // --- Borders ---
  static Color borderTertiary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF3A3A37)
          : const Color(0xFFD3D1C7);

  static Color borderSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF4A4A47)
          : const Color(0xFFB4B2A9);

  // --- Semantic ---
  static Color accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF7F77DD)
          : const Color(0xFF534AB7);

  static Color accentBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2A2740)
          : const Color(0xFFEEEDFE);

  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1D9E75)
          : const Color(0xFF0F6E56);

  static Color successBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0D2920)
          : const Color(0xFFE1F5EE);

  static Color danger(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFE24B4A)
          : const Color(0xFFA32D2D);

  static Color dangerBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2E1414)
          : const Color(0xFFFCEBEB);

  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFEF9F27)
          : const Color(0xFF854F0B);

  static Color warningBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2C1E08)
          : const Color(0xFFFAEEDA);

  // --- Tier badges ---
  static Color tierColor(BuildContext context, String tier) {
    switch (tier.toLowerCase()) {
      case 'premium advanced':
        return accent(context);
      case 'premium':
        return success(context);
      case 'standard':
        return const Color(0xFF378ADD);
      default:
        return textTertiary(context);
    }
  }

  static Color tierBg(BuildContext context, String tier) {
    switch (tier.toLowerCase()) {
      case 'premium advanced':
        return accentBg(context);
      case 'premium':
        return successBg(context);
      case 'standard':
        return Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0C2030)
            : const Color(0xFFE6F1FB);
      default:
        return bgTertiary(context);
    }
  }

  // --- Active / playing highlight ---
  static Color playingHighlight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2A2740)
          : const Color(0xFFEEEDFE);

  static Color playingText(BuildContext context) =>
      accent(context);
}

class GVTypography {
  GVTypography._();

  static const String fontFamily = 'sans-serif';

  static TextStyle display(BuildContext context) => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: GVColors.textPrimary(context),
        height: 1.3,
      );

  static TextStyle title(BuildContext context) => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: GVColors.textPrimary(context),
        height: 1.4,
      );

  static TextStyle heading(BuildContext context) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: GVColors.textPrimary(context),
        height: 1.5,
      );

  static TextStyle body(BuildContext context) => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: GVColors.textPrimary(context),
        height: 1.7,
      );

  static TextStyle bodySecondary(BuildContext context) => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: GVColors.textSecondary(context),
        height: 1.7,
      );

  static TextStyle small(BuildContext context) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: GVColors.textSecondary(context),
        height: 1.5,
      );

  static TextStyle label(BuildContext context) => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: GVColors.textSecondary(context),
        letterSpacing: 0.3,
        height: 1.4,
      );

  // For transcript / article reading
  static TextStyle reader(BuildContext context) => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        color: GVColors.textPrimary(context),
        height: 1.8,
        letterSpacing: 0.1,
      );

  static TextStyle readerActive(BuildContext context) => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w500,
        color: GVColors.playingText(context),
        height: 1.8,
        letterSpacing: 0.1,
      );
}

class GVSpacing {
  GVSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class GVRadius {
  GVRadius._();

  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double pill = 100;
}

class GVBorder {
  GVBorder._();

  static BoxBorder tertiary(BuildContext context) => Border.all(
        color: GVColors.borderTertiary(context),
        width: 0.5,
      );

  static BoxBorder secondary(BuildContext context) => Border.all(
        color: GVColors.borderSecondary(context),
        width: 0.5,
      );

  static BoxDecoration card(BuildContext context) => BoxDecoration(
        color: GVColors.bgPrimary(context),
        border: tertiary(context),
        borderRadius: BorderRadius.circular(GVRadius.lg),
      );

  static BoxDecoration surface(BuildContext context) => BoxDecoration(
        color: GVColors.bgSecondary(context),
        borderRadius: BorderRadius.circular(GVRadius.lg),
      );
}

// ── AppTheme ──────────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? const Color(0xFF7F77DD) : const Color(0xFF534AB7),
      onPrimary: Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF2A2740) : const Color(0xFFEEEDFE),
      onPrimaryContainer:
          isDark ? const Color(0xFFCECBF6) : const Color(0xFF26215C),
      secondary: isDark ? const Color(0xFF1D9E75) : const Color(0xFF0F6E56),
      onSecondary: Colors.white,
      secondaryContainer:
          isDark ? const Color(0xFF0D2920) : const Color(0xFFE1F5EE),
      onSecondaryContainer:
          isDark ? const Color(0xFF9FE1CB) : const Color(0xFF04342C),
      surface: isDark ? const Color(0xFF252523) : const Color(0xFFF5F4F0),
      onSurface:
          isDark ? const Color(0xFFEFEEE8) : const Color(0xFF1A1A18),
      surfaceContainerHighest:
          isDark ? const Color(0xFF2E2E2C) : const Color(0xFFECEBE6),
      onSurfaceVariant:
          isDark ? const Color(0xFF8A8A83) : const Color(0xFF5F5E5A),
      outline: isDark ? const Color(0xFF3A3A37) : const Color(0xFFD3D1C7),
      outlineVariant:
          isDark ? const Color(0xFF2E2E2C) : const Color(0xFFECEBE6),
      error: isDark ? const Color(0xFFE24B4A) : const Color(0xFFA32D2D),
      onError: Colors.white,
      errorContainer:
          isDark ? const Color(0xFF2E1414) : const Color(0xFFFCEBEB),
      onErrorContainer:
          isDark ? const Color(0xFFF7C1C1) : const Color(0xFF501313),
      inverseSurface:
          isDark ? const Color(0xFFEFEEE8) : const Color(0xFF1A1A18),
      onInverseSurface:
          isDark ? const Color(0xFF1A1A18) : const Color(0xFFEFEEE8),
      inversePrimary:
          isDark ? const Color(0xFF534AB7) : const Color(0xFF7F77DD),
      scrim: Colors.black54,
      shadow: Colors.black26,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF1A1A18) : const Color(0xFFF5F4F0),
      dividerColor: isDark ? const Color(0xFF3A3A37) : const Color(0xFFD3D1C7),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF3A3A37) : const Color(0xFFD3D1C7),
        thickness: 0.5,
        space: 0,
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF252523) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GVRadius.lg),
          side: BorderSide(
            color: isDark ? const Color(0xFF3A3A37) : const Color(0xFFD3D1C7),
            width: 0.5,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? const Color(0xFF1A1A18) : const Color(0xFFF5F4F0),
        foregroundColor:
            isDark ? const Color(0xFFEFEEE8) : const Color(0xFF1A1A18),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDark ? const Color(0xFFEFEEE8) : const Color(0xFF1A1A18),
        ),
        iconTheme: IconThemeData(
          color: isDark ? const Color(0xFF8A8A83) : const Color(0xFF5F5E5A),
          size: 20,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor:
            isDark ? const Color(0xFF1A1A18) : Colors.white,
        selectedItemColor:
            isDark ? const Color(0xFF7F77DD) : const Color(0xFF534AB7),
        unselectedItemColor:
            isDark ? const Color(0xFF555550) : const Color(0xFF888780),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF252523) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GVRadius.md),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF3A3A37) : const Color(0xFFD3D1C7),
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GVRadius.md),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF3A3A37) : const Color(0xFFD3D1C7),
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GVRadius.md),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF7F77DD) : const Color(0xFF534AB7),
            width: 1,
          ),
        ),
        hintStyle: TextStyle(
          color: isDark ? const Color(0xFF555550) : const Color(0xFF888780),
          fontSize: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isDark ? const Color(0xFF7F77DD) : const Color(0xFF534AB7),
          foregroundColor: Colors.white,
          elevation: 0,
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GVRadius.md),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor:
              isDark ? const Color(0xFFEFEEE8) : const Color(0xFF1A1A18),
          side: BorderSide(
            color: isDark ? const Color(0xFF3A3A37) : const Color(0xFFD3D1C7),
            width: 0.5,
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GVRadius.md),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor:
              isDark ? const Color(0xFF7F77DD) : const Color(0xFF534AB7),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GVRadius.md),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor:
            isDark ? const Color(0xFF252523) : const Color(0xFFF5F4F0),
        selectedColor:
            isDark ? const Color(0xFF2A2740) : const Color(0xFFEEEDFE),
        side: BorderSide(
          color: isDark ? const Color(0xFF3A3A37) : const Color(0xFFD3D1C7),
          width: 0.5,
        ),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: isDark ? const Color(0xFFEFEEE8) : const Color(0xFF1A1A18),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GVRadius.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor:
            isDark ? const Color(0xFF7F77DD) : const Color(0xFF534AB7),
        inactiveTrackColor:
            isDark ? const Color(0xFF3A3A37) : const Color(0xFFD3D1C7),
        thumbColor:
            isDark ? const Color(0xFF7F77DD) : const Color(0xFF534AB7),
        overlayColor: isDark
            ? const Color(0x207F77DD)
            : const Color(0x20534AB7),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: isDark ? const Color(0xFF8A8A83) : const Color(0xFF5F5E5A),
        textColor:
            isDark ? const Color(0xFFEFEEE8) : const Color(0xFF1A1A18),
        subtitleTextStyle: TextStyle(
          fontSize: 13,
          color: isDark ? const Color(0xFF8A8A83) : const Color(0xFF5F5E5A),
        ),
      ),
    );
  }
}
