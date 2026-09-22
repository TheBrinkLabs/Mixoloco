import 'package:android_id/android_id.dart';
import 'package:flutter/foundation.dart';

/// A per-(device, app signing key) identifier that survives a reinstall —
/// on Android, `Settings.Secure.ANDROID_ID`, read via the dedicated
/// android_id plugin. It only changes on a factory reset or if the app
/// switches signing keys, which is exactly what makes it useful for
/// spotting "this is the same phone that already has an account" reinstall
/// churn — see LeagueRepository.ensurePlayerDocument's use of it, and
/// tools/league-rollover/assignNewJoiners.js's pruneDuplicateDeviceAccounts.
///
/// Ported from Capitle's own device_id_service.dart, which carries a
/// deliberate warning worth keeping: this must read Settings.Secure.
/// ANDROID_ID specifically, NOT device_info_plus's AndroidDeviceInfo.id
/// (despite the name, that's Build.ID — the OS build fingerprint,
/// identical across every device on the same firmware, not per-device —
/// using it there once had server-side duplicate-account pruning treating
/// unrelated real players as reinstall duplicates).
///
/// Cached after the first successful read since it never changes for the
/// lifetime of an install. Returns null on non-Android platforms or if
/// the platform channel call fails — callers treat that as "can't tell,"
/// never as a hard error.
class DeviceIdService {
  String? _cached;

  Future<String?> getDeviceId() async {
    if (_cached != null) return _cached;
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final id = await const AndroidId().getId();
      if (id == null || id.isEmpty) return null;
      _cached = id;
      return id;
    } catch (e, st) {
      debugPrint('DeviceIdService failed to read Android ID (non-fatal): $e\n$st');
      return null;
    }
  }
}

final deviceIdService = DeviceIdService();
