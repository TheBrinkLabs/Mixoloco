import 'dart:async' show unawaited;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'analytics_service.dart';
import 'firebase_bootstrap.dart';

/// Wraps Firebase Anonymous Auth (the baseline identity every player gets,
/// invisibly, for the weekly league system) plus an optional "Sign in with
/// Google" upgrade that links the anonymous account to a real Google
/// credential so progress survives a reinstall or a new device — without
/// ever forcing a login screen on someone who just wants to play. Mirrors
/// Capitle's own AuthService.linkGoogle.
class AuthService {
  // main.dart kicks off initFirebase() fire-and-forget after runApp(), not
  // awaited before first paint — MenuScreen's own initState (itself firing
  // within that same first frame) was reaching these getters before that
  // completed, and FirebaseAuth.instance throws synchronously if
  // Firebase.initializeApp() hasn't resolved yet. ensureSignedIn already
  // guarded on firebaseAvailable for exactly this reason; these three
  // didn't, so every cold start logged an unhandled
  // "[core/no-app] No Firebase App '[DEFAULT]'" exception from
  // _maybeSyncProgress. Same safe-default shape as ensureSignedIn's own
  // early return.
  String? get uid => firebaseAvailable ? FirebaseAuth.instance.currentUser?.uid : null;

  bool get isLinkedToGoogle =>
      firebaseAvailable &&
      (FirebaseAuth.instance.currentUser?.providerData.any((p) => p.providerId == 'google.com') ?? false);

  String? get linkedGoogleEmail {
    if (!firebaseAvailable) return null;
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
  // GoogleAuthProvider.credential() to accept.
  static const _webClientId = '727783490936-behtcegpukusknibes1p8n4ghm155aeh.apps.googleusercontent.com';

  bool _googleInitialized = false;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId).timeout(const Duration(seconds: 10));
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
  ///
  /// Every step below is wrapped in its own [Future.timeout] — this used
  /// to have none at all, unlike [ensureSignedIn]'s own 8s guard, so a
  /// stuck native account picker, a flaky connection, or a Firebase Auth
  /// call that simply never resolves left the whole `await linkGoogle()`
  /// hanging forever. Every caller already sets a loading flag before
  /// this and clears it in a catch block once it throws — with no
  /// timeout anywhere, "throws" was exactly the thing that could never
  /// happen, so the UI's spinner just spun indefinitely with no way out
  /// short of force-closing the app. [_pickerTimeout] is deliberately
  /// much longer than the others since that step waits on a real human
  /// picking an account, not just a network round-trip.
  Future<GoogleLinkResult> linkGoogle() async {
    final result = await _linkGoogle();
    // Restoring an older linked account switches uid — keep analytics
    // and crash reports attributed to the account actually in use.
    analyticsService.setUserId(uid);
    final current = uid;
    if (current != null) {
      unawaited(FirebaseCrashlytics.instance.setUserIdentifier(current));
    }
    return result;
  }

  Future<GoogleLinkResult> _linkGoogle() async {
    await _ensureGoogleInitialized();
    final account = await GoogleSignIn.instance.authenticate().timeout(_pickerTimeout);
    final idToken = account.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      final result = await FirebaseAuth.instance.signInWithCredential(credential).timeout(_networkTimeout);
      await _forceFreshToken(result.user);
      return GoogleLinkResult(credential: result, restoredExistingAccount: result.additionalUserInfo?.isNewUser == false);
    }

    try {
      final result = await currentUser.linkWithCredential(credential).timeout(_networkTimeout);
      return GoogleLinkResult(credential: result, restoredExistingAccount: false);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        final result = await FirebaseAuth.instance.signInWithCredential(credential).timeout(_networkTimeout);
        await _forceFreshToken(result.user);
        return GoogleLinkResult(credential: result, restoredExistingAccount: true);
      }
      // Already linked to this exact current user (e.g. League's own
      // "Sign in with Google" tapped by someone who already linked from
      // Settings) — nothing to restore, just re-authenticate as the
      // already-correct account instead of surfacing a failure for a
      // call that didn't actually need to do anything.
      if (e.code == 'provider-already-linked') {
        final result = await FirebaseAuth.instance.signInWithCredential(credential).timeout(_networkTimeout);
        await _forceFreshToken(result.user);
        return GoogleLinkResult(credential: result, restoredExistingAccount: false);
      }
      rethrow;
    }
  }

  /// `signInWithCredential` swaps [FirebaseAuth.currentUser] to a
  /// *different* uid than whatever was active before (the whole point
  /// of the `credential-already-in-use` path — restoring the player's
  /// older, pre-existing linked account) — unlike `linkWithCredential`,
  /// which keeps the same uid throughout and never hit this. The SDK
  /// reports `currentUser.uid` as updated immediately, but Firestore's
  /// security rules check the *ID token's* own uid claim, and that
  /// token isn't always proactively refreshed just because the local
  /// `currentUser` object changed — confirmed live: every call this
  /// makes right afterward (progress_sync.dart's own 3-attempt retry
  /// included) failed with `permission-denied` identically across all
  /// three attempts, not just the first, meaning it wasn't settling on
  /// its own within that backoff window. Forcing a genuinely fresh
  /// token here (the `true` argument skips any locally cached one)
  /// means every caller downstream — not just this method's own
  /// immediate return — sees the correct uid from the very next
  /// Firestore call.
  Future<void> _forceFreshToken(User? user) async {
    try {
      await user?.getIdToken(true).timeout(_networkTimeout);
    } catch (e, st) {
      debugPrint('Forcing a fresh ID token failed (non-fatal): $e\n$st');
    }
  }

  static const _pickerTimeout = Duration(minutes: 2);
  static const _networkTimeout = Duration(seconds: 20);
}

class GoogleLinkResult {
  final UserCredential credential;
  final bool restoredExistingAccount;
  const GoogleLinkResult({required this.credential, required this.restoredExistingAccount});
}

final authService = AuthService();
