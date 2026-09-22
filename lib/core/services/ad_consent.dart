import 'package:shared_preferences/shared_preferences.dart';
import 'ad_service.dart';

/// GDPR/CCPA ad-consent state — shown once (see AdConsentScreen), then
/// re-applied on every subsequent launch without asking again. Plain
/// SharedPreferences calls rather than a Riverpod-provided instance,
/// matching how the rest of this app's persistence already works (see
/// progression_service.dart) rather than Capitle's provider-override
/// pattern.
class AdConsentService {
  static const _hasSeenKey = 'has_seen_ad_consent';
  static const _grantedKey = 'ad_consent_granted';

  static Future<bool> hasSeenAdConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenKey) ?? false;
  }

  static Future<bool> isGranted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_grantedKey) ?? false;
  }

  /// Persists the user's choice and (re)initializes LevelPlay with it.
  /// Safe to call again later if this ever gets a Settings re-entry point
  /// — AdService.initialize() no-ops the actual LevelPlay.init() call if
  /// already initialized, but always re-applies the consent flags first.
  static Future<void> recordAndApply(bool granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenKey, true);
    await prefs.setBool(_grantedKey, granted);
    await adService.initialize(consentGranted: granted);
  }

  /// Called on a normal cold start when consent was already decided in a
  /// previous session — just re-applies the stored choice.
  static Future<void> applyStoredConsent() async {
    await adService.initialize(consentGranted: await isGranted());
  }
}
