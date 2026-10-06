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

  // textLight/textMuted were tuned for the old dark AppColors.surface
  // dialog background — on the new light stone NotificationTablet (see
  // core/widgets/notification_tablet.dart) they read as washed-out to
  // invisible. These two are that same light-text/muted-text pairing's
  // dark-on-light mirror, for any text actually sitting on the stone.
  static const textOnStone = Color(0xFF3A2E22);
  static const textOnStoneMuted = Color(0xFF6B5D4F);

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
