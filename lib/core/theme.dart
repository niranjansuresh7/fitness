import 'package:flutter/material.dart';

/// The app's colours and typography.
///
/// Water is the primary subject, so the seed colour is a deep water blue and
/// the macro accents are picked to stay distinguishable from it and from each
/// other in both light and dark mode.
class AppTheme {
  const AppTheme._();

  static const Color water = Color(0xFF0A84FF);
  static const Color protein = Color(0xFFE0455F);
  static const Color carbs = Color(0xFFF0A02A);
  static const Color fat = Color(0xFF8E6FE0);
  static const Color fiber = Color(0xFF2FA36B);
  static const Color energy = Color(0xFF3E7BFA);
  static const Color warning = Color(0xFFD9822B);
  static const Color danger = Color(0xFFD03A3A);
  static const Color good = Color(0xFF2FA36B);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: water,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF6F7F9)
          : const Color(0xFF101215),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1B1E23),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      dividerTheme: const DividerThemeData(space: 1, thickness: 1),
    );
  }
}
