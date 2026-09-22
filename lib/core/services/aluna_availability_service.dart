import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether Aluna's Play Store listing has actually gone live yet —
/// ported from Capitle's own aluna_availability_service.dart (same
/// service, same cross-promoted app), used here as the fallback for
/// Mixoloco's own score-milestone MREC ad break (see aluna_mrec_ad.dart)
/// when the real ad network has nothing to show. Until Google is
/// actually serving a real page there, tapping through would just dump
/// the user on a broken/placeholder Play Store page. Checked once per
/// cold start in the background and cached — once confirmed live, it
/// stays live, so a later transient network hiccup can't regress a real
/// listing back to "coming soon".
class AlunaAvailabilityService {
  static const _prefKey = 'aluna_play_store_live';
  static const _playStoreUrl = 'https://play.google.com/store/apps/details?id=com.brinklabs.aluna';

  bool _isLive = false;

  bool get isLive => _isLive;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isLive = prefs.getBool(_prefKey) ?? false;
    if (_isLive) return; // already confirmed on a previous launch
    await _refresh(prefs);
  }

  Future<void> _refresh(SharedPreferences prefs) async {
    try {
      // A published listing returns 200; an unpublished/nonexistent
      // package id returns 404 — a plain GET is used over HEAD since
      // Play Store's edge doesn't reliably support HEAD the same way.
      final response = await http.get(Uri.parse(_playStoreUrl)).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        _isLive = true;
        await prefs.setBool(_prefKey, true);
      }
    } catch (_) {
      // Offline, timeout, or a Play Store hiccup — leave it as "not
      // live yet" and just try again next cold start.
    }
  }
}

final alunaAvailabilityService = AlunaAvailabilityService();
