import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

/// Legacy theme layer, being migrated onto the GatiVāni tokens in
/// design/tokens.dart (spec: docs/DESIGN_SYSTEM.md). GVColors/GVTypography
/// are deprecated — new code uses Gati / GatiType / GatiMotion. AppTheme
/// itself is rebuilt on the brand tokens (pasupu accent, Anek Telugu).
/// Flat, adaptive light/dark, no gradients, no glow.

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
          ? Gati.pasupuGlow
          : Gati.pasupuDeep;

  static Color accentBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? GatiDark.accentSoft
          : Gati.pasupuSoft;

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
          ? GatiDark.accentSoft
          : Gati.pasupuSoft;

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

// ── Category colors (18 categories) ─────────────────────────────────────────

class GVCategory {
  GVCategory._();

  static Color color(String category) {
    switch (category.toLowerCase()) {
      case 'international':       return const Color(0xFF1565C0);
      case 'national politics':   return const Color(0xFFBF360C);
      case 'state politics':      return const Color(0xFF6A1B9A);
      case 'editorial':           return const Color(0xFF37474F);
      case 'parliamentary affairs': return const Color(0xFF1B5E20);
      case 'national':            return const Color(0xFF0277BD);
      case 'state schemes':       return const Color(0xFF558B2F);
      case 'health':              return const Color(0xFFC62828);
      case 'environment':         return const Color(0xFF2E7D32);
      case 'judiciary':           return const Color(0xFF4527A0);
      case 'education':           return const Color(0xFFE65100);
      case 'ministry news':       return const Color(0xFF00695C);
      case 'prominent persons':   return const Color(0xFF4E342E);
      case 'trending news':       return const Color(0xFFAD1457);
      case 'viral news':          return const Color(0xFFFF6F00);
      case 'entertainment':       return const Color(0xFF7B1FA2);
      case 'sports':              return const Color(0xFF1565C0);
      case 'business':            return const Color(0xFF1B5E20);
      case 'politics':            return const Color(0xFFBF360C);
      case 'government':          return const Color(0xFF1B5E20);
      case 'news':                return Gati.pasupuGlow;
      default:                    return const Color(0xFF546E7A);
    }
  }

  static Color bg(String category) => color(category).withOpacity(0.12);

  static const List<String> all = [
    'International', 'National Politics', 'State Politics', 'Editorial',
    'Parliamentary Affairs', 'National', 'State Schemes', 'Health',
    'Environment', 'Judiciary', 'Education', 'Ministry News',
    'Prominent Persons', 'Trending News', 'Viral News',
    'Entertainment', 'Sports', 'Business',
  ];
}

// ── Tier subscription config ─────────────────────────────────────────────────

class TierConfig {
  TierConfig._();

  static const Map<String, int> _limitSeconds = {
    'free':                     5 * 60,
    'standard':                60 * 60,
    'premium':                 90 * 60,
    'super_premium':          120 * 60,
    'super_premium_advanced': 999 * 60, // effectively unlimited
  };

  static const Map<String, String> displayName = {
    'free':                     'Free',
    'standard':                 'Standard',
    'premium':                  'Premium',
    'super_premium':            'Super Premium',
    'super_premium_advanced':   'Super Premium Advanced',
  };

  static int limitSeconds(String tier) =>
      _limitSeconds[tier.toLowerCase()] ?? _limitSeconds['free']!;

  static String limitFormatted(String tier) {
    final mins = limitSeconds(tier) ~/ 60;
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = mins % 60;
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    }
    return '${mins} min';
  }

  static bool isUnlimited(String tier) =>
      tier.toLowerCase() == 'super_premium_advanced';
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
      primary: isDark ? Gati.pasupuGlow : Gati.pasupuDeep,
      onPrimary: isDark ? Gati.inkDeep : Colors.white,
      primaryContainer:
          isDark ? GatiDark.accentSoft : Gati.pasupuSoft,
      onPrimaryContainer:
          isDark ? Gati.pasupuGlow : Gati.pasupuDeep,
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
          isDark ? Gati.pasupuDeep : Gati.pasupuGlow,
      scrim: Colors.black54,
      shadow: Colors.black26,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: GoogleFonts.anekTelugu().fontFamily,
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
            isDark ? Gati.pasupuGlow : Gati.pasupuDeep,
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
            color: isDark ? Gati.pasupuGlow : Gati.pasupuDeep,
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
              isDark ? Gati.pasupuGlow : Gati.pasupuDeep,
          foregroundColor: isDark ? Gati.inkDeep : Colors.white,
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
              isDark ? Gati.pasupuGlow : Gati.pasupuDeep,
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
            isDark ? GatiDark.accentSoft : Gati.pasupuSoft,
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
            isDark ? Gati.pasupuGlow : Gati.pasupuDeep,
        inactiveTrackColor:
            isDark ? const Color(0xFF3A3A37) : const Color(0xFFD3D1C7),
        thumbColor:
            isDark ? Gati.pasupuGlow : Gati.pasupuDeep,
        overlayColor: isDark
            ? const Color(0x20F4B942)
            : const Color(0x209A6200),
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
