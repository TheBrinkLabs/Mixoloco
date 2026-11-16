import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/audio_settings_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/cocktail_mode_provider.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/device_id_service.dart';
import '../../../core/utils/nickname_generator.dart';
import '../../../core/utils/progress_sync.dart';
import '../../../core/widgets/notification_tablet.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/repositories/league_repository.dart';
import '../../../data/services/league_local_service.dart';
import '../../game/providers/game_state_provider.dart';
import 'about_screen.dart';

/// Music-in-menu, music-in-game, sound-effects, and language toggles —
/// grouped into AUDIO/GAMEPLAY/ACCOUNT per design_handoff_submenus'
/// Settings spec. Watches [audioSettingsProvider] directly (no local
/// mirrored state needed) since its setters update `state` synchronously
/// before persisting.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Cocktail Mode changes which items count toward a level-up (see
  /// GameStateNotifier._checkLevelUp) — safe to flip between runs, but
  /// flipping it mid-run would leave the live board's own
  /// completedCocktailIds/order chasing the OLD mode's rules. Rather
  /// than let that drift silently, a run actually in progress (same
  /// "inProgress" definition MenuScreen._playGame uses for its own
  /// Continue/New-Game offer) gets a confirm first, then an explicit
  /// restart-at-the-same-level (startNewGameAtLevel) — evolution tier,
  /// highest level reached, and credits are untouched by that call, only
  /// this run's table/score/order.
  Future<void> _handleCocktailModeChange(BuildContext context, WidgetRef ref, AppLocale locale, bool enabled) async {
    final board = ref.read(gameStateProvider);
    final inProgress = !board.gameOver && (board.score > 0 || board.placedItems.isNotEmpty);
    if (inProgress) {
      final confirmed = await showDialog<bool>(context: context, builder: (_) => _CocktailModeChangeDialog(locale: locale));
      if (confirmed != true) return;
      ref.read(gameStateProvider.notifier).startNewGameAtLevel(board.level);
    }
    await ref.read(cocktailModeProvider.notifier).setEnabled(enabled);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(audioSettingsProvider);
    final notifier = ref.read(audioSettingsProvider.notifier);
    final cocktailModeEnabled = ref.watch(cocktailModeProvider);
    final locale = ref.watch(localeProvider);

    return SubmenuScaffold(
      title: tr(locale, 'settings'),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GroupHeader(text: tr(locale, 'settings_group_audio')),
            InsetList(
              rows: [
                _ToggleRow(
                  icon: Icons.music_note_rounded,
                  label: tr(locale, 'music_in_menu'),
                  value: settings.menuMusicEnabled,
                  onChanged: notifier.setMenuMusicEnabled,
                ),
                _ToggleRow(
                  icon: Icons.videogame_asset_rounded,
                  label: tr(locale, 'music_in_game'),
                  value: settings.gameMusicEnabled,
                  onChanged: notifier.setGameMusicEnabled,
                ),
                _ToggleRow(
                  icon: Icons.graphic_eq_rounded,
                  label: tr(locale, 'sound_effects'),
                  value: settings.sfxEnabled,
                  onChanged: notifier.setSfxEnabled,
                ),
              ],
            ),
            GroupHeader(text: tr(locale, 'settings_group_gameplay')),
            InsetList(
              rows: [
                _ToggleRow(
                  icon: Icons.local_bar_rounded,
                  label: tr(locale, 'cocktail_mode'),
                  value: cocktailModeEnabled,
                  onChanged: (enabled) => _handleCocktailModeChange(context, ref, locale, enabled),
                ),
                _LanguageRow(
                  locale: locale,
                  onChanged: (next) => ref.read(localeProvider.notifier).setLocale(next),
                ),
              ],
            ),
            GroupHeader(text: tr(locale, 'settings_group_account')),
            InsetList(
              rows: [
                _NicknameRow(locale: locale),
                _GoogleBackupRow(locale: locale),
                _ChevronRow(
                  icon: Icons.info_rounded,
                  label: tr(locale, 'about'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ResetProgressButton(
              locale: locale,
              onReset: () => ref.read(gameStateProvider.notifier).resetProgression(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.icon, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SubmenuRow(
      icon: icon,
      label: label,
      trailing: _SettingsToggle(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}

/// The new toggle track/knob — replaces [PlankToggle] on this screen
/// family only (PlankToggle's own carved-wood look stays on the screens
/// that still use it).
class _SettingsToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SettingsToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 54,
        height: 30,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: value ? SubmenuColors.green : SubmenuColors.toggleOffTrack,
          border: Border.all(color: value ? SubmenuColors.greenEdge : SubmenuColors.toggleOffBorder, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0, 2))],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChevronRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ChevronRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SubmenuRow(
      icon: icon,
      label: label,
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
      onTap: onTap,
    );
  }
}

/// The Language row — tapping it opens a dropdown menu listing every
/// supported locale. Each language's own name is shown in that language
/// itself (a picker labeled "English"/"Español" rather than translating
/// "Spanish" into whatever's currently selected), which is how language
/// pickers conventionally read regardless of the app's own current
/// language.
class _LanguageRow extends StatelessWidget {
  final AppLocale locale;
  final ValueChanged<AppLocale> onChanged;
  const _LanguageRow({required this.locale, required this.onChanged});

  static String _name(AppLocale locale) => switch (locale) {
    AppLocale.en => 'English',
    AppLocale.es => 'Español',
    AppLocale.de => 'Deutsch',
    AppLocale.it => 'Italiano',
    AppLocale.ja => '日本語',
    AppLocale.ko => '한국어',
    AppLocale.nl => 'Nederlands',
    AppLocale.fr => 'Français',
    AppLocale.pt => 'Português',
  };

  @override
  Widget build(BuildContext context) {
    return SubmenuRow(
      icon: Icons.language_rounded,
      label: tr(locale, 'language'),
      trailing: PopupMenuButton<AppLocale>(
        initialValue: locale,
        onSelected: onChanged,
        color: SubmenuColors.panelBottom,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: SubmenuColors.ring)),
        itemBuilder: (context) => [
          for (final l in AppLocale.values)
            PopupMenuItem(
              value: l,
              child: Text(_name(l), style: GoogleFonts.luckiestGuy(fontSize: 14, color: l == locale ? SubmenuColors.gold : Colors.white)),
            ),
        ],
        child: SubmenuValuePill(text: _name(locale), icon: Icons.arrow_drop_down_rounded),
      ),
    );
  }
}

/// Lets a player change the name the Leaderboard shows for them after
/// its one-time setup screen (nickname_setup_screen.dart) — that screen
/// only ever runs once, the first time "Rankings" is tapped with no
/// nickname set, with no way back into it afterward. Loads the
/// locally-cached nickname on its own rather than watching
/// leagueControllerProvider, same reasoning as _GoogleBackupRow's own
/// doc comment — this is a lightweight local read, not worth a
/// Firestore round trip just to label a Settings row.
class _NicknameRow extends ConsumerStatefulWidget {
  final AppLocale locale;
  const _NicknameRow({required this.locale});

  @override
  ConsumerState<_NicknameRow> createState() => _NicknameRowState();
}

class _NicknameRowState extends ConsumerState<_NicknameRow> {
  String? _nickname = nicknameNotifier.value;

  void _onNicknameChanged() {
    if (mounted) setState(() => _nickname = nicknameNotifier.value);
  }

  @override
  void initState() {
    super.initState();
    // A Google sign-in on this same screen restores the account's
    // nickname via syncProgress — follow it rather than reading once.
    nicknameNotifier.addListener(_onNicknameChanged);
    loadNickname();
  }

  @override
  void dispose() {
    nicknameNotifier.removeListener(_onNicknameChanged);
    super.dispose();
  }

  Future<void> _edit() async {
    final result = await editNickname(context, ref, widget.locale, current: _nickname);
    if (result != null && mounted) setState(() => _nickname = result);
  }

  // Plain Text has no issue wrapping/overflowing like the old
  // ColorfulPlankText did, but the pill's width budget is still tight —
  // keep the same clip-to-10-chars safety net.
  static String _displayValue(String? nickname, AppLocale locale) {
    final raw = nickname ?? tr(locale, 'nickname_not_set');
    return raw.length > 10 ? '${raw.substring(0, 10)}…' : raw;
  }

  @override
  Widget build(BuildContext context) {
    return SubmenuRow(
      icon: Icons.person_rounded,
      label: tr(widget.locale, 'nickname_label'),
      trailing: SubmenuValuePill(text: _displayValue(_nickname, widget.locale), icon: Icons.edit_rounded),
      onTap: _edit,
    );
  }
}

/// The stone-tablet edit dialog itself — split out from
/// [_NicknameRowState._edit] since a TextField needs its own
/// StatefulWidget to manage focus/rebuilds on every keystroke without
/// rebuilding the whole Settings screen underneath it.
/// Opens the nickname dialog and saves the result (profile, Firestore,
/// local cache) — shared by Settings and the Global rankings tab. Returns
/// the new nickname, or null if cancelled or the save failed (a snackbar
/// says so).
Future<String?> editNickname(BuildContext context, WidgetRef ref, AppLocale locale, {String? current}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (context) => _NicknameEditDialog(locale: locale, initialText: current ?? generateFallbackNickname()),
  );
  if (result == null || !context.mounted) return null;
  try {
    await authService.ensureSignedIn();
    final uid = authService.uid;
    if (uid == null) throw Exception('not signed in');
    final repo = ref.read(leagueRepositoryProvider);
    await repo.ensurePlayerDocument(uid: uid, nickname: result, deviceId: await deviceIdService.getDeviceId());
    await repo.syncNickname(uid: uid, nickname: result);
    await saveNickname(result);
    return result;
  } catch (e, st) {
    debugPrint('Nickname save failed: $e\n$st');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(locale, 'edit_nickname_failed'))));
    }
    return null;
  }
}

class _NicknameEditDialog extends StatefulWidget {
  final AppLocale locale;
  final String initialText;
  const _NicknameEditDialog({required this.locale, required this.initialText});

  @override
  State<_NicknameEditDialog> createState() => _NicknameEditDialogState();
}

class _NicknameEditDialogState extends State<_NicknameEditDialog> {
  // Owned here, not by the caller: the dialog's closing animation keeps
  // rebuilding the TextField after showDialog returns, so the controller
  // must outlive that — disposing it in the caller crashed the field.
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = tr(widget.locale, 'edit_nickname_empty_error'));
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NotificationTablet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(widget.locale, 'edit_nickname_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textOnStone),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLength: 20,
              autofocus: true,
              textAlign: TextAlign.center,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textOnStone),
              decoration: InputDecoration(
                hintText: tr(widget.locale, 'edit_nickname_hint'),
                hintStyle: const TextStyle(color: AppColors.textOnStoneMuted),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.2),
                counterStyle: const TextStyle(color: AppColors.textOnStoneMuted, fontSize: 11),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.coral)),
            ],
            const SizedBox(height: 12),
            StoneButton(
              onTap: _submit,
              child: Text(tr(widget.locale, 'save'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black)),
            ),
            const SizedBox(height: 10),
            StoneButton(
              onTap: () => Navigator.of(context).pop(),
              height: 40,
              child: Text(tr(widget.locale, 'cancel'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Links the anonymous account to a real Google credential so progress
/// (credits, evolution tiers, level, local high scores — see
/// progress_sync.dart) survives a reinstall or a new device — see
/// AuthService.linkGoogle. A ConsumerStatefulWidget of its own (rather
/// than folding into SettingsScreen) since the linked/not-linked status
/// isn't itself a Riverpod-watched value (FirebaseAuth's own current-user
/// state), so this needs its own setState after a successful sign-in.
class _GoogleBackupRow extends ConsumerStatefulWidget {
  final AppLocale locale;
  const _GoogleBackupRow({required this.locale});

  @override
  ConsumerState<_GoogleBackupRow> createState() => _GoogleBackupRowState();
}

class _GoogleBackupRowState extends ConsumerState<_GoogleBackupRow> {
  late bool _linked = authService.isLinkedToGoogle;

  Future<void> _handleTap() async {
    if (_linked) {
      // Already linked — treat a tap as "check again," not just a label
      // lookup. This is also the only retry path for a sync that failed
      // the first time around (see the comment below on why that's a
      // real, not just theoretical, possibility).
      final uid = authService.uid;
      final outcome = uid == null
          ? ProgressSyncOutcome.failed
          : await syncProgress(ref.read(leagueRepositoryProvider), uid);
      if (outcome == ProgressSyncOutcome.changed) {
        await ref.read(gameStateProvider.notifier).refreshLifetimeFieldsFromDisk();
      }
      if (!mounted) return;
      final email = authService.linkedGoogleEmail;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome == ProgressSyncOutcome.failed
                ? tr(widget.locale, 'google_sign_in_restore_failed')
                : (email ?? tr(widget.locale, 'connected')),
          ),
        ),
      );
      return;
    }
    try {
      final result = await authService.linkGoogle();
      final uid = authService.uid;
      // Pulls down whatever this Google account already has on record
      // and merges it with whatever this device played anonymously
      // before signing in — see progress_sync.dart's own doc for why
      // this is a safe max()-per-field merge rather than an overwrite
      // either direction. syncProgress can genuinely fail (a transient
      // permission-denied right after the account switch above is the
      // likeliest real-world case — the auth token backing Firestore's
      // own permission checks hasn't necessarily finished propagating
      // the instant linkGoogle() returns) and retries internally, but a
      // caller still has to treat "failed" as its own outcome rather
      // than silently falling through to the success message below —
      // that's exactly what let a sync failure look identical to "there
      // was nothing to restore" before this was fixed.
      final outcome = uid == null
          ? ProgressSyncOutcome.failed
          : await syncProgress(ref.read(leagueRepositoryProvider), uid);
      if (outcome == ProgressSyncOutcome.changed) {
        await ref.read(gameStateProvider.notifier).refreshLifetimeFieldsFromDisk();
      }
      if (!mounted) return;
      setState(() => _linked = true);
      final messageKey = outcome == ProgressSyncOutcome.failed
          ? 'google_sign_in_restore_failed'
          : (result.restoredExistingAccount ? 'google_sign_in_restored' : 'google_sign_in_backed_up');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.locale, messageKey))),
      );
    } catch (e, st) {
      debugPrint('Google sign-in link failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(widget.locale, 'google_sign_in_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SubmenuRow(
      icon: Icons.cloud_upload_rounded,
      label: tr(widget.locale, 'back_up_progress'),
      onTap: _handleTap,
      trailing: _linked
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(widget.locale, 'backed_up'),
                  style: const TextStyle(fontFamily: 'Nunito', fontSize: 12, fontWeight: FontWeight.w900, color: SubmenuColors.greenBright),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SubmenuColors.green,
                    border: Border.all(color: SubmenuColors.greenEdge, width: 2),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
                ),
              ],
            )
          : SubmenuValuePill(text: tr(widget.locale, 'sign_in_with_google'), icon: Icons.login_rounded),
    );
  }
}

/// The confirm step [SettingsScreen._handleCocktailModeChange] shows
/// before flipping Cocktail Mode mid-run.
class _CocktailModeChangeDialog extends StatelessWidget {
  final AppLocale locale;
  const _CocktailModeChangeDialog({required this.locale});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NotificationTablet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(locale, 'cocktail_mode_change_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textOnStone),
            ),
            const SizedBox(height: 8),
            Text(
              tr(locale, 'cocktail_mode_change_body'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textOnStoneMuted),
            ),
            const SizedBox(height: 20),
            StoneButton(
              onTap: () => Navigator.of(context).pop(true),
              child: Text(tr(locale, 'cocktail_mode_change_confirm'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black)),
            ),
            const SizedBox(height: 10),
            StoneButton(
              onTap: () => Navigator.of(context).pop(false),
              height: 40,
              child: Text(tr(locale, 'cancel'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black)),
            ),
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
/// dialog since it isn't reversible — unlike every toggle/picker above,
/// this one changes game data, not a preference.
class _ResetProgressButton extends StatelessWidget {
  final AppLocale locale;
  final VoidCallback onReset;
  const _ResetProgressButton({required this.locale, required this.onReset});

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: NotificationTablet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(locale, 'reset_progress_confirm_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textOnStone),
              ),
              const SizedBox(height: 8),
              Text(
                tr(locale, 'reset_progress_confirm_body'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textOnStoneMuted),
              ),
              const SizedBox(height: 20),
              StoneButton(
                onTap: () => Navigator.of(context).pop(true),
                child: Text(tr(locale, 'reset_progress_button'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black)),
              ),
              const SizedBox(height: 10),
              StoneButton(
                onTap: () => Navigator.of(context).pop(false),
                height: 40,
                child: Text(tr(locale, 'cancel'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black)),
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
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SubmenuColors.resetBorder, width: 2),
          color: SubmenuColors.red.withValues(alpha: 0.12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restart_alt_rounded, color: SubmenuColors.resetText, size: 20),
            const SizedBox(width: 8),
            Text(
              tr(locale, 'reset_progress').toUpperCase(),
              style: const TextStyle(fontFamily: 'Lilita One', fontSize: 16, color: SubmenuColors.resetText),
            ),
          ],
        ),
      ),
    );
  }
}
