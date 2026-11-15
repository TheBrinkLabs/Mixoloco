import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/utils/device_id_service.dart';
import '../../../core/utils/nickname_generator.dart';
import '../../../core/utils/progress_sync.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/widgets/notification_tablet.dart' show StoneButton;
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/repositories/league_repository.dart';
import '../../../data/services/league_local_service.dart';
import '../../game/providers/game_state_provider.dart';
import '../../league/screens/rankings_screen.dart';

/// One-time setup before a player's first visit to the leaderboard —
/// gold/navy styled to match every other sub-menu screen (Settings,
/// Guide, etc.) rather than its old one-off plain-dark look. Lays out
/// the three real ways a player can end up here as two clearly separate
/// choices, same shape other games use (a prominent "Sign in with
/// Google" option, a plainer guest path below it):
///
///  (a) Pick a nickname, skip Google — a fresh anonymous guest profile.
///  (b) Pick a nickname, then sign in with Google — same fresh profile,
///      now backed up (this is what happens when [_restoreWithGoogle]
///      links a Google account that's never been used with Mixoloco
///      before; [GoogleLinkResult.restoredExistingAccount] comes back
///      false, so the nickname field's own value is left alone).
///  (c) Sign in with Google first — if that account's been used before,
///      this restores the player's old nickname and progress outright,
///      skipping manual nickname entry entirely.
///
/// Shown lazily the first time "Leaderboard" is tapped from the menu,
/// rather than during any app-launch flow, since Mixoloco has no
/// first-launch onboarding carousel to hook into.
class NicknameSetupScreen extends ConsumerStatefulWidget {
  const NicknameSetupScreen({super.key});

  @override
  ConsumerState<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends ConsumerState<NicknameSetupScreen> {
  late final TextEditingController _controller;
  bool _saving = false;
  bool _restoring = false;
  String? _error;

  /// Set right before handing off to RankingsScreen on success — see
  /// [dispose]'s own comment for why this matters.
  bool _handedOffToLeague = false;

  /// Restores the bottom banner; captured in initState because Riverpod 3
  /// throws if ref is used inside dispose().
  late final void Function() _restoreBanner;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: generateFallbackNickname());
    // The persistent bottom banner (see banner_ad_widget.dart) otherwise
    // overlaps this screen's own bottom-anchored Continue button — found
    // by hand on-device: the button visually renders but taps land on
    // the banner sitting on top of it instead. Same fix GameScreen uses
    // for the same reason.
    ref.read(bannerPositionProvider.notifier).state = BannerPosition.hidden;
    final bannerNotifier = ref.read(bannerPositionProvider.notifier);
    _restoreBanner = () => Future.microtask(() => bannerNotifier.state = BannerPosition.bottom);
  }

  @override
  void dispose() {
    // Only restore the banner here when this screen is going away WITHOUT
    // handing off to RankingsScreen (e.g. the player backed out) — pushing
    // RankingsScreen's Global tab already hides it itself (that tab's own
    // initState), but Navigator.pushReplacement mounts the new route and
    // runs its initState *before* disposing this one, not after, so an
    // unconditional reset here would run second and stomp its own
    // correct "hidden" state right back to visible.
    if (!_handedOffToLeague) {
      _restoreBanner();
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_saving) return;
    final locale = ref.read(localeProvider);
    final nickname = _controller.text.trim();
    if (nickname.isEmpty) {
      setState(() => _error = tr(locale, 'edit_nickname_empty_error'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await authService.ensureSignedIn();
      final uid = authService.uid;
      if (uid == null) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = tr(locale, 'nickname_setup_connect_error');
        });
        return;
      }

      final repo = ref.read(leagueRepositoryProvider);
      await repo.ensurePlayerDocument(uid: uid, nickname: nickname, deviceId: await deviceIdService.getDeviceId());
      await repo.syncNickname(uid: uid, nickname: nickname);
      await saveNickname(nickname);

      if (!mounted) return;
      _handedOffToLeague = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RankingsScreen(initialTab: RankingsTab.global)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = tr(locale, 'nickname_setup_generic_error');
      });
    }
  }

  /// A player reinstalling (or switching devices) previously had no way
  /// to tell this screen "I've played before" — it always started them
  /// on a brand-new, empty profile with a freshly generated nickname,
  /// even if they'd reached Level 3 under a Google-linked account before.
  /// The only restore path lived in Settings, well past the point a new
  /// install would ever naturally find it. This offers the same
  /// AuthService.linkGoogle()+syncProgress() restore right at the moment
  /// it's actually needed. See progress_sync.dart's own doc for why
  /// syncProgress can genuinely fail (and must be treated as its own
  /// outcome, not silently treated as "nothing to restore") rather than
  /// just surfacing whatever Firebase Auth's account-linking step did.
  Future<void> _restoreWithGoogle() async {
    if (_restoring || _saving) return;
    final locale = ref.read(localeProvider);
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      final result = await authService.linkGoogle();
      final uid = authService.uid;
      final outcome = uid == null
          ? ProgressSyncOutcome.failed
          : await syncProgress(ref.read(leagueRepositoryProvider), uid);
      if (outcome == ProgressSyncOutcome.failed) {
        if (!mounted) return;
        setState(() {
          _restoring = false;
          _error = tr(locale, 'google_sign_in_restore_failed');
        });
        return;
      }
      if (outcome == ProgressSyncOutcome.changed) {
        await ref.read(gameStateProvider.notifier).refreshLifetimeFieldsFromDisk();
      }
      // A restored account already has its own nickname on record —
      // reuse it instead of leaving the freshly generated fallback in
      // the field, same spirit as every other field this restores.
      if (result.restoredExistingAccount && uid != null) {
        final snap = await ref.read(leagueRepositoryProvider).getPlayer(uid);
        final existingNickname = snap.data()?['nickname'] as String?;
        if (existingNickname != null && existingNickname.isNotEmpty) {
          _controller.text = existingNickname;
        }
      }
      if (!mounted) return;
      setState(() => _restoring = false);
      // Completes the same way tapping Continue would — the account's
      // now Google-linked (ensureSignedIn inside _continue no-ops, it's
      // already signed in) and the nickname field holds either the
      // restored name or whatever was there before, so this is exactly
      // the normal flow from here.
      await _continue();
    } catch (e, st) {
      debugPrint('Google restore failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error = tr(locale, 'google_sign_in_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final busy = _saving || _restoring;

    return SubmenuScaffold(
      title: tr(locale, 'league_profile_title'),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // (c) — and half of (b): a Google account that's already
            // been used with Mixoloco restores its old nickname/progress
            // outright; a brand-new one just backs up whatever nickname
            // is in the field below once this completes.
            Opacity(
              opacity: _saving ? 0.5 : 1.0,
              child: GestureDetector(
                onTap: busy ? null : _restoreWithGoogle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: SubmenuColors.gold, width: 2),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [SubmenuColors.cardTop, SubmenuColors.cardBottom],
                    ),
                    boxShadow: [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      _restoring
                          ? const SizedBox(
                              width: 32,
                              height: 32,
                              child: Padding(
                                padding: EdgeInsets.all(6),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                            )
                          : const IconBadge(icon: Icons.login_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              tr(locale, 'nickname_setup_google_button'),
                              style: const TextStyle(fontFamily: 'Lilita One', fontSize: 16, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr(locale, 'nickname_setup_google_subtitle'),
                              style: submenuNunito(size: 11, weight: FontWeight.w700, color: SubmenuColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Container(height: 1, color: SubmenuColors.ring)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    tr(locale, 'or_label'),
                    style: const TextStyle(fontFamily: 'Lilita One', fontSize: 12, color: SubmenuColors.textSecondary),
                  ),
                ),
                Expanded(child: Container(height: 1, color: SubmenuColors.ring)),
              ],
            ),
            const SizedBox(height: 16),
            // (a) — and where (b)'s own nickname comes from: a guest
            // profile under whatever name is typed here, no Google
            // involved unless the card above is used instead/afterward.
            GroupHeader(text: tr(locale, 'nickname_label')),
            InsetList(
              rows: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: TextField(
                    controller: _controller,
                    maxLength: 20,
                    style: const TextStyle(fontFamily: 'Lilita One', fontSize: 18, color: Colors.white),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: tr(locale, 'edit_nickname_hint'),
                      hintStyle: const TextStyle(color: SubmenuColors.textDisabled),
                      border: InputBorder.none,
                      counterStyle: submenuNunito(size: 11, weight: FontWeight.w700, color: SubmenuColors.textDisabled),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                tr(locale, 'nickname_setup_subtitle'),
                style: submenuNunito(size: 12, weight: FontWeight.w700, color: SubmenuColors.textSecondary),
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                tr(locale, 'nickname_setup_guest_note'),
                style: submenuNunito(size: 12, weight: FontWeight.w700, color: SubmenuColors.textDisabled),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: submenuNunito(size: 12, weight: FontWeight.w800, color: SubmenuColors.resetText),
              ),
            ],
            const SizedBox(height: 20),
            StoneButton(
              onTap: busy ? null : _continue,
              height: 52,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text(tr(locale, 'continue_label'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
            ),
            // Clears the persistent bottom banner (hidden for this whole
            // screen, see initState) so nothing sits flush against it.
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}
