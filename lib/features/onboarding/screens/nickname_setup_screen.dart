import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/device_id_service.dart';
import '../../../core/utils/nickname_generator.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../data/repositories/league_repository.dart';
import '../../../data/services/league_local_service.dart';
import '../../league/screens/league_screen.dart';

/// One-time setup before a player's first visit to the leaderboard —
/// just a nickname (no country flag/Google-linking yet, unlike Capitle's
/// own profile_setup_screen.dart; both are easy to add later without
/// touching this shape). Shown lazily the first time "Leaderboard" is
/// tapped from the menu, rather than during any app-launch flow, since
/// Mixoloco has no first-launch onboarding carousel to hook into.
class NicknameSetupScreen extends ConsumerStatefulWidget {
  const NicknameSetupScreen({super.key});

  @override
  ConsumerState<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends ConsumerState<NicknameSetupScreen> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  /// Set right before handing off to LeagueScreen on success — see
  /// [dispose]'s own comment for why this matters.
  bool _handedOffToLeague = false;

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
  }

  @override
  void dispose() {
    // Only restore the banner here when this screen is going away WITHOUT
    // handing off to LeagueScreen (e.g. the player backed out) — pushing
    // LeagueScreen already hides it itself (its own initState), but
    // Navigator.pushReplacement mounts the new route and runs its
    // initState *before* disposing this one, not after, so an
    // unconditional reset here would run second and stomp LeagueScreen's
    // own correct "hidden" state right back to visible.
    if (!_handedOffToLeague) {
      ref.read(bannerPositionProvider.notifier).state = BannerPosition.bottom;
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
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LeagueScreen()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = tr(locale, 'nickname_setup_generic_error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 16),
              Text(
                tr(locale, 'nickname_setup_title'),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: -0.5),
              ),
              const SizedBox(height: 6),
              Text(
                tr(locale, 'nickname_setup_subtitle'),
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              Text(
                tr(locale, 'nickname_label').toUpperCase(),
                style: const TextStyle(fontSize: 10, letterSpacing: 2.5, fontWeight: FontWeight.w700, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                maxLength: 20,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textLight),
                decoration: InputDecoration(
                  hintText: tr(locale, 'edit_nickname_hint'),
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  counterStyle: const TextStyle(color: AppColors.textMuted),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.coral)),
              ],
              const Spacer(),
              GestureDetector(
                onTap: _saving ? null : _continue,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(gradient: AppColors.gradientSunset, borderRadius: BorderRadius.circular(15)),
                  child: Center(
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text(tr(locale, 'continue_label'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
