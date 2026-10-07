// 🎯 Dart imports:
import 'dart:developer';

// 📦 Package imports:
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

// 🌎 Project imports:
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

  @override
  Future<void> deleteAccount() async {
    // A sign-in that is on its way, such as the one that the start of the app asks for, could make an account after
    // this call found none, so the call waits for it. The attempt never throws.
    await _attempt;
    await _initializeApp();
    final auth = _auth ?? FirebaseAuth.instance;
    final user = auth.currentUser;
    // No account on the device: none was made, or an earlier call deleted it.
    if (user == null) return;
    try {
      // The FlutterFire documentation of `User.delete` says that `requires-recent-login` "does not apply if the user
      // is anonymous" (firebase_auth 6.7.0, lib/src/user.dart). The account cannot sign in again to fix it either,
      // so the code is not caught here and the caller reports a failure of this step.
      await user.delete();
    } on FirebaseAuthException catch (error) {
      // An earlier delete reached the backend and its answer did not reach the app.
      if (error.code != 'user-not-found') rethrow;
      await auth.signOut();
    }
  }

  @override
  Future<bool> hasPaidEntitlement() async {
    try {
      // A sign-in that is on its way could make the account that this call reads. The attempt never throws.
      await _attempt;
      await _initializeApp();
      final user = (_auth ?? FirebaseAuth.instance).currentUser;
      // The call never signs in: no account holds no entitlement.
      if (user == null) return false;
      // A cached token can keep a claim that the extension removed after an expiry or a transfer, so the call asks
      // for a newly issued token each time.
      final claim = (await user.getIdTokenResult(true)).claims?['revenueCatEntitlements'];
      // As `paid()` in `firestore.rules` reads the claim: a list that holds `basic` or `pro`.
      return claim is List && claim.any((entitlement) => entitlement == 'basic' || entitlement == 'pro');
    } on Object catch (error, stackTrace) {
      // A missing network, a disabled account, or a platform without Firebase: the report keeps the footer.
      log('The entitlement claim is unavailable: $error', stackTrace: stackTrace);
      return false;
    }
  }

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
