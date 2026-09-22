import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/ad_consent.dart';
import 'core/services/aluna_availability_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/firebase_bootstrap.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/banner_ad_widget.dart';
import 'core/widgets/bar_backdrop.dart';
import 'features/menu/screens/ad_consent_screen.dart';
import 'features/menu/screens/menu_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Full-screen/immersive — hides the status bar (clock, battery, wifi
  // icons) and nav bar; a swipe from the edge reveals them briefly, then
  // they auto-hide again. Matches how a game, not a regular app screen,
  // is expected to use the whole display.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Registers Bgm's own app-lifecycle observer, so menu music correctly
  // pauses/resumes around the app being backgrounded rather than playing
  // straight through it.
  FlameAudio.bgm.initialize();
  runApp(const ProviderScope(child: MixolocoApp()));
  // Fire-and-forget, same as ad init — nothing in the app depends on a
  // signed-in uid yet (the league feature this is laying groundwork for
  // isn't built), so there's no reason to delay first paint on it. No-ops
  // safely until a real Firebase project exists for Mixoloco (see
  // core/services/auth_service.dart's doc comment for exactly what's
  // still needed there).
  _initFirebaseAndAuth();
  // Also fire-and-forget — see aluna_availability_service.dart. Checked
  // once here so the MREC ad-break's Aluna fallback (see
  // ad_break_screen.dart) doesn't need to re-check on every single fill
  // failure.
  alunaAvailabilityService.init();
}

Future<void> _initFirebaseAndAuth() async {
  await initFirebase();
  await authService.ensureSignedIn();
}

class MixolocoApp extends StatefulWidget {
  const MixolocoApp({super.key});

  @override
  State<MixolocoApp> createState() => _MixolocoAppState();
}

class _MixolocoAppState extends State<MixolocoApp> {
  // Null while the one-time "has ad consent already been decided" check
  // is in flight — a plain SharedPreferences read, fast enough that a
  // bare backdrop (no board/content) for that one frame or two reads as
  // a normal launch flicker rather than a real loading screen.
  bool? _hasSeenAdConsent;

  @override
  void initState() {
    super.initState();
    _checkConsent();
  }

  Future<void> _checkConsent() async {
    final seen = await AdConsentService.hasSeenAdConsent();
    // GDPR requires consent to be collected before ad SDKs run — only
    // initialize LevelPlay immediately when a past choice already exists;
    // a first-time "not yet seen" case waits for AdConsentScreen's answer
    // (see _onAdConsentAnswered below).
    if (seen) await AdConsentService.applyStoredConsent();
    if (mounted) setState(() => _hasSeenAdConsent = seen);
  }

  Future<void> _onAdConsentAnswered(BuildContext context, bool granted) async {
    await AdConsentService.recordAndApply(granted);
    if (mounted) setState(() => _hasSeenAdConsent = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mixoloco',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Layers the single persistent banner ad above everything — see
      // banner_ad_widget.dart for why this lives here instead of inside
      // individual screens.
      builder: (context, child) {
        return Stack(children: [child!, const PersistentBannerAd()]);
      },
      home: switch (_hasSeenAdConsent) {
        null => const Scaffold(body: BarBackdrop(showTable: false, showHeaderBoard: false, child: SizedBox.shrink())),
        false => AdConsentScreen(onAnswered: _onAdConsentAnswered),
        true => const MenuScreen(),
      },
    );
  }
}
