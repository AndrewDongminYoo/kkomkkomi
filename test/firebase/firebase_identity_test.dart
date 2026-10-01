import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/firebase/firebase.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth;

class _MockUserCredential extends Mock implements UserCredential;

class _MockUser extends Mock implements User;

void main() {
  late FirebaseAuth auth;
  late int starts;

  /// What the next starts of Firebase throw, in order. A start without an entry works.
  late List<Object> startFailures;

  Future<void> initializeApp() async {
    starts++;
    if (startFailures.isNotEmpty) Error.throwWithStackTrace(startFailures.removeAt(0), StackTrace.current);
  }

  // mocktail refuses a `when` inside the answer of another stub, so a test makes its users and credentials before
  // it stubs the sign-in.
  User userWithId(String uid) {
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    return user;
  }

  UserCredential credentialOf(User? user) {
    final credential = _MockUserCredential();
    when(() => credential.user).thenReturn(user);
    return credential;
  }

  FirebaseIdentity identity() => FirebaseIdentity(initializeApp: initializeApp, auth: auth);

  setUp(() {
    auth = _MockFirebaseAuth();
    starts = 0;
    startFailures = [];
    when(() => auth.currentUser).thenReturn(null);
  });

  group('FirebaseIdentity', () {
    test('reaches Firebase only when the user ID is asked for', () {
      identity();

      expect(starts, 0);
      verifyZeroInteractions(auth);
    });

    test('starts Firebase, signs in anonymously, and gives the ID of the new account', () async {
      final credential = credentialOf(userWithId('user-1'));
      when(() => auth.signInAnonymously()).thenAnswer((_) async {
        // The sign-in comes after the start, because Firebase Auth needs the app.
        expect(starts, 1);
        return credential;
      });

      expect(await identity().currentUserId(), 'user-1');
      verify(() => auth.signInAnonymously()).called(1);
    });

    test('gives the ID of the account that the device holds, without a new sign-in', () async {
      final kept = userWithId('user-kept');
      when(() => auth.currentUser).thenReturn(kept);

      expect(await identity().currentUserId(), 'user-kept');
      expect(starts, 1);
      verifyNever(() => auth.signInAnonymously());
    });

    for (final (kind, failure) in <(String, Object)>[
      ('an exception', Exception('no native config')),
      ('an error', StateError('no plugin')),
    ]) {
      test('gives null when the start of Firebase fails with $kind, and signs in nothing', () async {
        startFailures.add(failure);

        expect(await identity().currentUserId(), isNull);
        verifyZeroInteractions(auth);
      });
    }

    for (final (kind, failure) in <(String, Object)>[
      ('a missing network', FirebaseAuthException(code: 'network-request-failed')),
      ('a refused anonymous sign-in', FirebaseAuthException(code: 'operation-not-allowed')),
      ('an error', StateError('no plugin')),
    ]) {
      test('gives null when the sign-in fails with $kind', () async {
        when(() => auth.signInAnonymously()).thenAnswer((_) => Future.error(failure));

        expect(await identity().currentUserId(), isNull);
      });
    }

    test('gives null when the sign-in gives no account', () async {
      final credential = credentialOf(null);
      when(() => auth.signInAnonymously()).thenAnswer((_) async => credential);

      expect(await identity().currentUserId(), isNull);
    });

    test('starts Firebase again at the call after a start that failed', () async {
      startFailures.add(Exception('no native config'));
      final credential = credentialOf(userWithId('user-1'));
      when(() => auth.signInAnonymously()).thenAnswer((_) async => credential);
      final identity = FirebaseIdentity(initializeApp: initializeApp, auth: auth);

      expect(await identity.currentUserId(), isNull);
      expect(await identity.currentUserId(), 'user-1');
      expect(starts, 2);
    });

    test('signs in again at the call after a sign-in that failed', () async {
      final credential = credentialOf(userWithId('user-1'));
      final answers = <Future<UserCredential> Function()>[
        () => Future.error(FirebaseAuthException(code: 'network-request-failed')),
        () async => credential,
      ];
      when(() => auth.signInAnonymously()).thenAnswer((_) => answers.removeAt(0)());
      final identity = FirebaseIdentity(initializeApp: initializeApp, auth: auth);

      expect(await identity.currentUserId(), isNull);
      expect(await identity.currentUserId(), 'user-1');
      verify(() => auth.signInAnonymously()).called(2);
    });

    test('makes one sign-in for two calls at one time, and gives both the same ID', () async {
      final signIn = Completer<UserCredential>();
      final credential = credentialOf(userWithId('user-1'));
      when(() => auth.signInAnonymously()).thenAnswer((_) => signIn.future);
      final identity = FirebaseIdentity(initializeApp: initializeApp, auth: auth);

      final first = identity.currentUserId();
      final second = identity.currentUserId();
      signIn.complete(credential);

      expect(await Future.wait([first, second]), ['user-1', 'user-1']);
      expect(starts, 1);
      verify(() => auth.signInAnonymously()).called(1);
    });

    test('makes one attempt for two calls at one time when the attempt fails, and a new one after it', () async {
      final signIn = Completer<UserCredential>();
      final credential = credentialOf(userWithId('user-1'));
      final answers = <Future<UserCredential> Function()>[
        () => signIn.future,
        () async => credential,
      ];
      when(() => auth.signInAnonymously()).thenAnswer((_) => answers.removeAt(0)());
      final identity = FirebaseIdentity(initializeApp: initializeApp, auth: auth);

      final first = identity.currentUserId();
      final second = identity.currentUserId();
      signIn.completeError(FirebaseAuthException(code: 'network-request-failed'));

      expect(await Future.wait([first, second]), [null, null]);
      expect(await identity.currentUserId(), 'user-1');
      verify(() => auth.signInAnonymously()).called(2);
    });
  });
}
