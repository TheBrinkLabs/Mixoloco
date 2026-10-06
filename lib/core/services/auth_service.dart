import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_bootstrap.dart';

/// Wraps Firebase Anonymous Auth (the baseline identity every player gets,
/// invisibly, for the weekly league system) plus an optional "Sign in with
/// Google" upgrade that links the anonymous account to a real Google
/// credential so progress survives a reinstall or a new device — without
/// ever forcing a login screen on someone who just wants to play. Mirrors
/// Capitle's own AuthService.linkGoogle.
class AuthService {
  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  bool get isLinkedToGoogle =>
      FirebaseAuth.instance.currentUser?.providerData.any((p) => p.providerId == 'google.com') ?? false;

  String? get linkedGoogleEmail {
    final providers = FirebaseAuth.instance.currentUser?.providerData ?? const [];
    for (final p in providers) {
      if (p.providerId == 'google.com') return p.email;
    }
    return null;
  }

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

  // The web (client_type: 3) OAuth client from Mixoloco's own
  // google-services.json — needed as serverClientId so the ID token
  // GoogleSignIn returns is audienced correctly for Firebase's
  // GoogleAuthProvider.credential() to accept. Only exists once Google
  // Sign-In is enabled for the mixoloco-dcb85 Firebase project AND the
  // app's signing SHA-1 is registered against it (see Project Settings ->
  // your apps) — until then this stays a placeholder and linkGoogle()
  // will fail (non-fatally; the Settings row just shows an error).
  static const _webClientId = 'TODO_MIXOLOCO_GOOGLE_WEB_CLIENT_ID';

  bool _googleInitialized = false;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    _googleInitialized = true;
  }

  /// Upgrades the current anonymous account to be backed by a Google
  /// account, preserving the same league profile/history. If this Google
  /// account is already linked to a different (older) anonymous UID — e.g.
  /// the user reinstalled and got a fresh anonymous UID, then signs back in
  /// with the Google account they used before — Firebase rejects the link
  /// with `credential-already-in-use`; in that case this signs in with that
  /// credential directly instead, which switches the active UID to the
  /// pre-existing linked account. [GoogleLinkResult.restoredExistingAccount]
  /// tells callers which case happened, so they can show "welcome back,
  /// restoring your previous progress" instead of treating it as a silent
  /// identity swap.
  Future<GoogleLinkResult> linkGoogle() async {
    await _ensureGoogleInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      return GoogleLinkResult(credential: result, restoredExistingAccount: result.additionalUserInfo?.isNewUser == false);
    }

    try {
      final result = await currentUser.linkWithCredential(credential);
      return GoogleLinkResult(credential: result, restoredExistingAccount: false);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        final result = await FirebaseAuth.instance.signInWithCredential(credential);
        return GoogleLinkResult(credential: result, restoredExistingAccount: true);
      }
      rethrow;
    }
  }
}

class GoogleLinkResult {
  final UserCredential credential;
  final bool restoredExistingAccount;
  const GoogleLinkResult({required this.credential, required this.restoredExistingAccount});
}

final authService = AuthService();
