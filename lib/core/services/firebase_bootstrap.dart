import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Whether Firebase finished initializing successfully. League features
/// must check this before touching Auth/Firestore — no google-services.json
/// exists for Mixoloco yet (see auth_service.dart's doc comment for what's
/// still needed), so this currently always ends up false; once that's in
/// place, a real outage or bad config should still degrade gracefully
/// rather than crash the app, since everything else in Mixoloco works
/// entirely offline/local today. Mirrors Capitle's own
/// core/services/firebase_bootstrap.dart exactly.
bool firebaseAvailable = false;

Future<void> initFirebase() async {
  try {
    await Firebase.initializeApp();
    firebaseAvailable = true;
  } catch (e, st) {
    debugPrint('Firebase init failed (league features will be unavailable): $e\n$st');
    firebaseAvailable = false;
  }
}
