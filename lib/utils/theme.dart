import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand colors (same for both modes)
  static const Color primary   = Color(0xFF7C3AED); // rich purple (from logo)
  static const Color teal      = Color(0xFF2DD4BF); // teal accent (from logo)
  static const Color accent    = Color(0xFFEC4899); // pink
  static const Color secondary = Color(0xFF8B5CF6); // lighter purple
  static const Color success   = Color(0xFF22C55E);
  static const Color warning   = Color(0xFFF59E0B);
  static const Color destructive = Color(0xFFEF4444);

  // ── DARK MODE ──────────────────────────────────────────────────────────────
  static const Color darkBg        = Color(0xFF0D0B1A); // deep dark purple-black
  static const Color darkSurface   = Color(0xFF1A1530); // elevated surface
  static const Color darkCard      = Color(0xFF221D3A); // card bg
  static const Color darkGlass     = Color(0x1AFFFFFF);
  static const Color darkBorder    = Color(0x33FFFFFF);
  static const Color darkFg        = Color(0xFFF1F5F9);
  static const Color darkMuted     = Color(0xFF94A3B8);

  // ── LIGHT MODE ─────────────────────────────────────────────────────────────
  static const Color lightBg       = Color(0xFFF5F3FF); // very light lavender
  static const Color lightSurface  = Color(0xFFFFFFFF);
  static const Color lightCard     = Color(0xFFEDE9FE); // light purple card
  static const Color lightGlass    = Color(0x1A7C3AED);
  static const Color lightBorder   = Color(0x337C3AED);
  static const Color lightFg       = Color(0xFF1E1B4B); // deep purple text
  static const Color lightMuted    = Color(0xFF6B7280);

  // Convenience getters used in widgets
  static Color bg(bool dark)      => dark ? darkBg      : lightBg;
  static Color surface(bool dark) => dark ? darkSurface : lightSurface;
  static Color card(bool dark)    => dark ? darkCard     : lightCard;
  static Color glass(bool dark)   => dark ? darkGlass    : lightGlass;
  static Color border(bool dark)  => dark ? darkBorder   : lightBorder;
  static Color fg(bool dark)      => dark ? darkFg       : lightFg;
  static Color muted(bool dark)   => dark ? darkMuted    : lightMuted;

  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bgColor  = isDark ? darkBg      : lightBg;
    final fgColor  = isDark ? darkFg      : lightFg;
    final srfColor = isDark ? darkSurface : lightSurface;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bgColor,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: Colors.white,
        secondary: teal,
        onSecondary: isDark ? darkBg : lightBg,
        error: destructive,
        onError: Colors.white,
        surface: srfColor,
        onSurface: fgColor,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ).apply(bodyColor: fgColor, displayColor: fgColor),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: fgColor,
      ),
    );
  }
}

class AppConstants {
  static const List<String> categories = [
    'Food', 'Transport', 'Shopping', 'Entertainment', 'Bills', 'Health', 'Others'
  ];
  static const List<String> moods = ['Happy', 'Neutral', 'Sad', 'Stressed', 'Tired'];
  static const List<String> paymentModes = ['Cash', 'Card', 'UPI'];
  static const List<String> emergencyReasons = [
    'Medical', 'Family', 'Urgent Bill', 'Other'
  ];

  static const Map<String, String> categoryEmojis = {
    'Food': '🍔',
    'Transport': '🚗',
    'Shopping': '🛍️',
    'Entertainment': '🎬',
    'Bills': '📄',
    'Health': '💊',
    'Others': '📦',
  };
}
