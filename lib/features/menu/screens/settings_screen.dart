import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/audio_settings_provider.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/wood_plank.dart';
import '../../game/providers/game_state_provider.dart';

/// Music-in-menu, music-in-game, sound-effects, and language toggles —
/// its own pushed screen (matching Best Scores/the main menu) rather
/// than a modal sheet, so every "list of things on wood planks" page in
/// the app reads as the same family. Watches [audioSettingsProvider]
/// directly (no local mirrored state needed) since its setters update
/// `state` synchronously before persisting.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(audioSettingsProvider);
    final notifier = ref.read(audioSettingsProvider.notifier);
    final locale = ref.watch(localeProvider);
    final screenSize = MediaQuery.sizeOf(context);
    const sideMargin = 28.0;
    final plankWidth = screenSize.width - sideMargin * 2;
    final plankHeight = plankWidth / kMenuBoard3Aspect;

    return Scaffold(
      body: BarBackdrop(
        showTable: false,
        showHeaderBoard: false,
        child: Stack(
          children: [
            Positioned(left: 12, top: 10, child: PlankBackButton(onTap: () => Navigator.of(context).pop())),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WoodTitlePlank(
                      title: tr(locale, 'settings'),
                      icon: Icons.settings_rounded,
                      width: plankWidth,
                      height: plankHeight,
                      assetPath: 'assets/images/menu_board_3.png',
                      iconAsset: 'assets/images/settings.png',
                    ),
                    const SizedBox(height: 10),
                    _SettingPlankRow(
                      icon: Icons.music_note_rounded,
                      label: tr(locale, 'music_in_menu'),
                      value: settings.menuMusicEnabled,
                      onChanged: notifier.setMenuMusicEnabled,
                      width: plankWidth,
                      height: plankHeight,
                    ),
                    const SizedBox(height: 10),
                    _SettingPlankRow(
                      icon: Icons.videogame_asset_rounded,
                      label: tr(locale, 'music_in_game'),
                      value: settings.gameMusicEnabled,
                      onChanged: notifier.setGameMusicEnabled,
                      width: plankWidth,
                      height: plankHeight,
                    ),
                    const SizedBox(height: 10),
                    _SettingPlankRow(
                      icon: Icons.graphic_eq_rounded,
                      label: tr(locale, 'sound_effects'),
                      value: settings.sfxEnabled,
                      onChanged: notifier.setSfxEnabled,
                      width: plankWidth,
                      height: plankHeight,
                    ),
                    const SizedBox(height: 10),
                    _LanguagePlankRow(
                      label: tr(locale, 'language'),
                      value: locale,
                      onChanged: (next) => ref.read(localeProvider.notifier).setLocale(next),
                      width: plankWidth,
                      height: plankHeight,
                    ),
                    const SizedBox(height: 10),
                    _ResetProgressPlankRow(
                      locale: locale,
                      onReset: () => ref.read(gameStateProvider.notifier).resetProgression(),
                      width: plankWidth,
                      height: plankHeight,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingPlankRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final double width;
  final double height;
  const _SettingPlankRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return WoodPlank(
      width: width,
      height: height,
      assetPath: 'assets/images/menu_board_3.png',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.06),
        child: Row(
          children: [
            Icon(icon, size: height * 0.3, color: kPlankIconColor, shadows: kPlankIconShadows),
            SizedBox(width: width * 0.03),
            Expanded(
              child: ColorfulPlankText(
                text: label,
                fontSize: height * 0.22,
                variant: kPlankTextVariant,
                font: kPlankTextFont,
                shadowStyle: kPlankShadowStyle,
              ),
            ),
            PlankToggle(value: value, onChanged: onChanged, height: height),
          ],
        ),
      ),
    );
  }
}

/// The Language row — two selectable pill buttons instead of a switch.
/// Each language's own name is shown in that language itself (a picker
/// labeled "English"/"Español" rather than translating "Spanish" into
/// whatever's currently selected), which is how language pickers
/// conventionally read regardless of the app's own current language.
class _LanguagePlankRow extends StatelessWidget {
  final String label;
  final AppLocale value;
  final ValueChanged<AppLocale> onChanged;
  final double width;
  final double height;
  const _LanguagePlankRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return WoodPlank(
      width: width,
      height: height,
      assetPath: 'assets/images/menu_board_3.png',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.06),
        child: Row(
          children: [
            Icon(Icons.language_rounded, size: height * 0.3, color: kPlankIconColor, shadows: kPlankIconShadows),
            SizedBox(width: width * 0.03),
            // Expanded (not Flexible+Spacer) — Flexible alongside a
            // Spacer split the row's leftover width 50/50 between them,
            // which starved a plain word like "Language" of room it
            // didn't actually need and wrapped it into "LANG"/"UAGE" for
            // no reason. Expanded alone claims all the leftover width in
            // one place, leaving the dropdown pill its fixed size.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ColorfulPlankText(
                  text: label,
                  fontSize: height * 0.22,
                  variant: kPlankTextVariant,
                  font: kPlankTextFont,
                  shadowStyle: kPlankShadowStyle,
                ),
              ),
            ),
            _LanguageDropdown(value: value, onChanged: onChanged, height: height),
          ],
        ),
      ),
    );
  }
}

/// A single pill showing the current language — tapping it opens a
/// dropdown menu listing every supported locale (just English/Español
/// for now), replacing the old side-by-side chip pair per feedback
/// that a picker naming just the active choice, with the rest a tap
/// away, reads cleaner than showing every option at once.
class _LanguageDropdown extends StatelessWidget {
  final AppLocale value;
  final ValueChanged<AppLocale> onChanged;
  final double height;
  const _LanguageDropdown({required this.value, required this.onChanged, required this.height});

  static String _name(AppLocale locale) => locale == AppLocale.en ? 'English' : 'Español';

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppLocale>(
      initialValue: value,
      onSelected: onChanged,
      color: const Color(0xFF3A2A18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.black.withValues(alpha: 0.4))),
      itemBuilder: (context) => [
        for (final locale in AppLocale.values)
          PopupMenuItem(
            value: locale,
            child: Text(
              _name(locale),
              style: GoogleFonts.luckiestGuy(fontSize: height * 0.16, color: locale == value ? AppColors.sunsetGold : Colors.white),
            ),
          ),
      ],
      // A carved wood-grain pill — the same bevel/gradient language the
      // toggle track and plank rows use — with the language name in
      // ColorfulPlankText's own orange combo, in place of the old flat
      // Material-orange rectangle with plain white text that read as a
      // generic app-chrome control dropped onto the wood.
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: height * 0.14, vertical: height * 0.07),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8B5A2B), Color(0xFF5A3818)]),
          border: Border.all(color: const Color(0xFF3B2412), width: 1.3),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 2)),
            BoxShadow(color: Colors.white24, blurRadius: 0, offset: Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorfulPlankText(
              text: _name(value),
              fontSize: height * 0.17,
              variant: PlankTextVariant.sunsetGradient,
              font: kPlankTextFont,
              shadowStyle: PlankShadowStyle.hardOffset,
            ),
            SizedBox(width: height * 0.03),
            Icon(Icons.arrow_drop_down_rounded, color: AppColors.sunsetGold, size: height * 0.26),
          ],
        ),
      ),
    );
  }
}

/// "Reset Progress" — puts the lifetime evolution-tier/level record back
/// to a fresh install's starting point (see
/// GameStateNotifier.resetProgression), for a player who's reached
/// Level 2 and wants to play the beach bar again from scratch rather
/// than every new game starting on the rooftop. Behind a confirmation
/// dialog since it isn't reversible — unlike every toggle/dropdown else
/// on this screen, this one changes game data, not a preference.
class _ResetProgressPlankRow extends StatelessWidget {
  final AppLocale locale;
  final VoidCallback onReset;
  final double width;
  final double height;
  const _ResetProgressPlankRow({required this.locale, required this.onReset, required this.width, required this.height});

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(locale, 'reset_progress_confirm_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textLight),
              ),
              const SizedBox(height: 8),
              Text(
                tr(locale, 'reset_progress_confirm_body'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(true),
                child: Container(
                  width: double.infinity,
                  height: 46,
                  decoration: BoxDecoration(gradient: AppColors.gradientSunset, borderRadius: BorderRadius.circular(14)),
                  child: Center(
                    child: Text(tr(locale, 'reset_progress_button'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(false),
                child: SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: Center(
                    child: Text(tr(locale, 'cancel'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) onReset();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _confirm(context),
      child: WoodPlank(
        width: width,
        height: height,
        assetPath: 'assets/images/menu_board_3.png',
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: width * 0.06),
          child: Row(
            children: [
              Icon(Icons.restart_alt_rounded, size: height * 0.3, color: kPlankIconColor, shadows: kPlankIconShadows),
              SizedBox(width: width * 0.03),
              Expanded(
                child: ColorfulPlankText(
                  text: tr(locale, 'reset_progress'),
                  fontSize: height * 0.2,
                  variant: kPlankTextVariant,
                  font: kPlankTextFont,
                  shadowStyle: kPlankShadowStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
