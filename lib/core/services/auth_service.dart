import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'firebase_bootstrap.dart';

/// Wraps Firebase Anonymous Auth — the baseline identity every player needs
/// for the weekly league system (see the league feature plan), assigned
/// invisibly on first launch, no login screen. This is step one of that
/// build: just the stable per-install uid every later piece (league
/// membership, weekly score submission, promotion) keys off. A "Sign in
/// with Google" upgrade (so progress survives a reinstall/new device,
/// mirroring Capitle's own AuthService.linkGoogle) is a later addition,
/// not needed to get the league system itself working.
///
/// Needs a real Firebase project before any of this actually does
/// anything: register com.brinklabs.mixoloco as a new Android app in the
/// Firebase console (a NEW project, not Capitle's — separate bundle id),
/// enable the Anonymous sign-in provider under Authentication, download
/// the resulting google-services.json to android/app/, then apply the
/// com.google.gms.google-services Gradle plugin (see Capitle's own
/// android/build.gradle.kts + android/app/build.gradle.kts for the exact
/// two-line pattern) — all of that needs your Google account, so it's
/// left for you to do. Until then [ensureSignedIn] just no-ops
/// (firebaseAvailable stays false) rather than crashing.
class AuthService {
  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  /// Signs in anonymously if there's no current user yet. Safe to call on
  /// every app launch. Never throws — on failure (offline cold start,
  /// Firebase misconfigured/not yet set up, etc.) [uid] just stays null
  /// and league features treat that as "unavailable for now."
  Future<void> ensureSignedIn({Duration timeout = const Duration(seconds: 8)}) async {
    if (!firebaseAvailable) return;
    if (FirebaseAuth.instance.currentUser != null) return;
    try {
      await FirebaseAuth.instance.signInAnonymously().timeout(timeout);
    } catch (e, st) {
      debugPrint('Anonymous sign-in failed (non-fatal): $e\n$st');
    }
  }
}

final authService = AuthService();
