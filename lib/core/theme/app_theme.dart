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

  // Named for the old light-stone NotificationTablet (see
  // core/widgets/notification_tablet.dart) these were tuned against —
  // that tablet is now a gold-rimmed navy panel instead (matching the
  // sub-menu redesign's own styling), so these are white/light-blue
  // rather than dark. Kept under the same names since every dialog's
  // *body* text (titles, hints, status messages) still reaches for
  // "whatever reads on the tablet" — button labels are a separate case
  // (see StoneButton's own doc: those stay dark, since the button itself
  // is still a light gold surface even though the tablet behind it isn't).
  static const textOnStone = Colors.white;
  static const textOnStoneMuted = Color(0xFFA9CDEB);

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
