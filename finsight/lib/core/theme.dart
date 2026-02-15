import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// FinSight Premium Dark Skeuomorphic Theme
///
/// Design language: Deep navy backgrounds, warm gold accents,
/// embossed cards with inner shadows, beveled edges, realistic depth.
class AppTheme {
  AppTheme._();

  // ── Color Palette ──────────────────────────────────────────────────
  static const Color background = Color(0xFF0A0E1A);
  static const Color surface = Color(0xFF141B2D);
  static const Color surfaceLight = Color(0xFF1A2340);
  static const Color surfaceBorder = Color(0xFF232D47);

  static const Color gold = Color(0xFFFFD700);
  static const Color goldLight = Color(0xFFFFE44D);
  static const Color goldDark = Color(0xFFB8960F);

  static const Color cyan = Color(0xFF00E5FF);
  static const Color cyanDark = Color(0xFF0097A7);

  static const Color success = Color(0xFF00E676);
  static const Color successDark = Color(0xFF00A152);
  static const Color error = Color(0xFFFF5252);
  static const Color errorDark = Color(0xFFD32F2F);

  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textMuted = Color(0xFF616161);

  // ── Category Colors ────────────────────────────────────────────────
  static const Map<String, Color> categoryColors = {
    'shopping': Color(0xFFFF6B6B),
    'food': Color(0xFFFFA726),
    'travel': Color(0xFF42A5F5),
    'bills': Color(0xFFAB47BC),
    'salary': Color(0xFF66BB6A),
    'transfer': Color(0xFF26C6DA),
    'entertainment': Color(0xFFEC407A),
    'health': Color(0xFFEF5350),
    'education': Color(0xFF5C6BC0),
    'investment': Color(0xFF7CB342),
    'emi': Color(0xFFFF7043),
    'recharge': Color(0xFF78909C),
    'other': Color(0xFFBDBDBD),
  };

  static const Map<String, IconData> categoryIcons = {
    'shopping': Icons.shopping_bag_rounded,
    'food': Icons.restaurant_rounded,
    'travel': Icons.flight_rounded,
    'bills': Icons.receipt_long_rounded,
    'salary': Icons.account_balance_wallet_rounded,
    'transfer': Icons.swap_horiz_rounded,
    'entertainment': Icons.movie_rounded,
    'health': Icons.local_hospital_rounded,
    'education': Icons.school_rounded,
    'investment': Icons.trending_up_rounded,
    'emi': Icons.credit_card_rounded,
    'recharge': Icons.phone_android_rounded,
    'other': Icons.help_outline_rounded,
  };

  // ── Gradients ──────────────────────────────────────────────────────
  static const LinearGradient goldGradient = LinearGradient(
    colors: [gold, goldLight, gold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [surfaceLight, surface],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient incomeGradient = LinearGradient(
    colors: [Color(0xFF00E676), Color(0xFF00C853)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient expenseGradient = LinearGradient(
    colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Shadows (Skeuomorphic) ─────────────────────────────────────────
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withAlpha(100),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: surfaceLight.withAlpha(50),
      blurRadius: 10,
      offset: const Offset(0, -2),
    ),
  ];

  static List<BoxShadow> get embossedShadow => [
    BoxShadow(
      color: Colors.black.withAlpha(120),
      blurRadius: 12,
      offset: const Offset(4, 4),
    ),
    BoxShadow(
      color: surfaceLight.withAlpha(40),
      blurRadius: 12,
      offset: const Offset(-4, -4),
    ),
  ];

  static List<BoxShadow> get innerGlow => [
    BoxShadow(color: gold.withAlpha(15), blurRadius: 30, spreadRadius: -5),
  ];

  // ── Border Radius ──────────────────────────────────────────────────
  static BorderRadius get cardRadius => BorderRadius.circular(20);
  static BorderRadius get chipRadius => BorderRadius.circular(12);
  static BorderRadius get buttonRadius => BorderRadius.circular(14);

  // ── Decorations ────────────────────────────────────────────────────
  static BoxDecoration get skeuCard => BoxDecoration(
    gradient: cardGradient,
    borderRadius: cardRadius,
    border: Border.all(color: surfaceBorder, width: 1),
    boxShadow: cardShadow,
  );

  static BoxDecoration get embossedCard => BoxDecoration(
    gradient: cardGradient,
    borderRadius: cardRadius,
    border: Border.all(color: surfaceBorder.withAlpha(150), width: 1.5),
    boxShadow: embossedShadow,
  );

  static BoxDecoration glowCard(Color glowColor) => BoxDecoration(
    gradient: cardGradient,
    borderRadius: cardRadius,
    border: Border.all(color: glowColor.withAlpha(60), width: 1),
    boxShadow: [
      BoxShadow(
        color: glowColor.withAlpha(30),
        blurRadius: 20,
        spreadRadius: -2,
      ),
      ...cardShadow,
    ],
  );

  // ── Theme Data ─────────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: gold,
      secondary: cyan,
      surface: surface,
      error: error,
      onPrimary: background,
      onSecondary: background,
      onSurface: textPrimary,
      onError: Colors.white,
      primaryContainer: surfaceLight,
      secondaryContainer: cyanDark,
    ),
    useMaterial3: true,
    textTheme: GoogleFonts.outfitTextTheme(
      ThemeData.dark().textTheme,
    ).apply(bodyColor: textPrimary, displayColor: textPrimary),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.outfit(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      iconTheme: const IconThemeData(color: gold),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: gold.withAlpha(30),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: gold,
          );
        }
        return GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: gold, size: 24);
        }
        return const IconThemeData(color: textMuted, size: 24);
      }),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: cardRadius),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceLight,
      selectedColor: gold.withAlpha(30),
      labelStyle: GoogleFonts.inter(fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: chipRadius),
      side: BorderSide(color: surfaceBorder),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceLight,
      contentTextStyle: GoogleFonts.inter(color: textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(
      color: surfaceBorder.withAlpha(100),
      thickness: 0.5,
    ),
  );
}
