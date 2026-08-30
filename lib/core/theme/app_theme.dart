import 'package:flutter/material.dart';

/// Tropical-bar palette — warm sunset oranges against deep teal, matching
/// the beachside cocktail-bar setting (see the reference screenshot used
/// when this project was scoped: a golden-hour beach bar).
class AppColors {
  AppColors._();

  static const bg = Color(0xFF0E2A2E); // deep teal, dodgy-bar-at-night base
  static const surface = Color(0xFF163B40);
  static const surface2 = Color(0xFF1E4A50);

  static const sunsetOrange = Color(0xFFFF8A3D);
  static const sunsetGold = Color(0xFFFFC15E);
  static const coral = Color(0xFFFF6B5B);
  static const mint = Color(0xFF4ECDC4);

  static const textLight = Color(0xFFFFF6EC);
  static const textMuted = Color(0xFFB9D6D4);

  static const gradientSunset = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [sunsetOrange, coral],
  );
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.sunsetOrange,
      brightness: Brightness.dark,
      surface: AppColors.surface,
    ),
    // No custom font bundled yet — add one under assets/fonts and set
    // fontFamily here once branding/type is picked.
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.textLight),
    ),
  );
}
