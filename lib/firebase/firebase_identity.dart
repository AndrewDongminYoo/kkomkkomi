import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:kkomkkomi/application/application.dart';

/// Starts Firebase, signs in anonymously, and gives the ID of that account.
///
/// Nothing reaches Firebase before the first call of [currentUserId]. A call that fails gives null, and the next
/// call starts Firebase and signs in again, so a launch without a network does not leave the app without identity
/// until its next launch.
final class FirebaseIdentity implements Identity {
  /// The `initializeApp` and `auth` arguments replace Firebase in a test.
  new({this._initializeApp = Firebase.initializeApp, this._auth});

  final Future<void> Function() _initializeApp;
  final FirebaseAuth? _auth;

  /// The attempt that is on its way, so that two calls at one time make one sign-in and not two accounts.
  Future<String?>? _attempt;

  @override
  Future<String?> currentUserId() => _attempt ??= _startAndSignIn().whenComplete(() => _attempt = null);

  Future<String?> _startAndSignIn() async {
    try {
      // The call gives no options, so Firebase reads the native config file of the platform, and no tracked file
      // imports the generated options. A call after the first one gives the app that the first one made.
      await _initializeApp();
      final auth = _auth ?? FirebaseAuth.instance;
      // Firebase keeps the account on the device, so only the first sign-in needs the network.
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      return user?.uid;
    } on Object catch (error, stackTrace) {
      // Firebase fails with an `Exception` for a refused sign-in or a missing network, and a platform without a
      // native config or without the plugin can fail with an `Error`. The app must open in each case, so the clause
      // catches every object.
      log('Firebase identity is unavailable: $error', stackTrace: stackTrace);
      return null;
    }
  }
}
