import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth_service.dart';
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
    ref.read(bannerPositionProvider.notifier).state = BannerPosition.bottom;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_saving) return;
    final nickname = _controller.text.trim();
    if (nickname.isEmpty) {
      setState(() => _error = "Enter a nickname to continue");
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
        setState(() {
          _saving = false;
          _error = "Couldn't connect — check your connection and try again";
        });
        return;
      }

      final repo = ref.read(leagueRepositoryProvider);
      await repo.ensurePlayerDocument(uid: uid, nickname: nickname, deviceId: await deviceIdService.getDeviceId());
      await repo.syncNickname(uid: uid, nickname: nickname);
      await saveNickname(nickname);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LeagueScreen()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "Something went wrong — try again in a bit";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              const Text(
                'Set up your league profile',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: -0.5),
              ),
              const SizedBox(height: 6),
              const Text(
                "This is what other players see on the leaderboard.",
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              const Text('NICKNAME', style: TextStyle(fontSize: 10, letterSpacing: 2.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                maxLength: 20,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textLight),
                decoration: InputDecoration(
                  hintText: 'Enter a nickname…',
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
                        : const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black)),
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
