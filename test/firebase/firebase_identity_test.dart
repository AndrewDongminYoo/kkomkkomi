// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/firebase/firebase.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth;

class _MockUserCredential extends Mock implements UserCredential;

class _MockUser extends Mock implements User;

class _MockIdTokenResult extends Mock implements IdTokenResult;

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

    group('deleteAccount', () {
      test('starts Firebase and deletes the account that the device holds', () async {
        final user = userWithId('user-1');
        when(user.delete).thenAnswer((_) async {
          // The delete comes after the start, because Firebase Auth needs the app.
          expect(starts, 1);
        });
        when(() => auth.currentUser).thenReturn(user);

        await identity().deleteAccount();

        verify(user.delete).called(1);
        verifyNever(() => auth.signInAnonymously());
      });

      test('waits for a sign-in that is on its way, and deletes the account that it makes', () async {
        final signIn = Completer<UserCredential>();
        final user = userWithId('user-1');
        final credential = credentialOf(user);
        when(user.delete).thenAnswer((_) async {});
        when(() => auth.signInAnonymously()).thenAnswer((_) => signIn.future);
        final identity = FirebaseIdentity(initializeApp: initializeApp, auth: auth);

        final startedAtLaunch = identity.currentUserId();
        await pumpEventQueue();
        final deletion = identity.deleteAccount();
        await pumpEventQueue();
        verifyNever(user.delete);

        when(() => auth.currentUser).thenReturn(user);
        signIn.complete(credential);
        await startedAtLaunch;
        await deletion;

        verify(user.delete).called(1);
      });

      test('does nothing when the device holds no account, and never signs in', () async {
        await identity().deleteAccount();

        expect(starts, 1);
        verifyNever(() => auth.signInAnonymously());
      });

      test('treats an account that the backend no longer has as deleted, and signs out of it', () async {
        final user = userWithId('user-1');
        when(user.delete).thenThrow(FirebaseAuthException(code: 'user-not-found'));
        when(() => auth.currentUser).thenReturn(user);
        when(() => auth.signOut()).thenAnswer((_) async {});

        await identity().deleteAccount();

        verify(() => auth.signOut()).called(1);
      });

      for (final code in ['network-request-failed', 'requires-recent-login']) {
        test('throws when the delete fails with $code', () async {
          final user = userWithId('user-1');
          when(user.delete).thenThrow(FirebaseAuthException(code: code));
          when(() => auth.currentUser).thenReturn(user);

          await expectLater(
            identity().deleteAccount(),
            throwsA(isA<FirebaseAuthException>().having((error) => error.code, 'code', code)),
          );
          verifyNever(() => auth.signOut());
        });
      }

      test('throws when Firebase does not start', () async {
        startFailures.add(Exception('no native config'));

        await expectLater(identity().deleteAccount(), throwsException);
        verifyZeroInteractions(auth);
      });
    });

    group('hasPaidEntitlement', () {
      /// A user whose newly issued token holds [claims].
      User userWithClaims(Map<String, dynamic>? claims) {
        final user = userWithId('user-1');
        final token = _MockIdTokenResult();
        when(() => token.claims).thenReturn(claims);
        when(() => user.getIdTokenResult(any())).thenAnswer((_) async => token);
        when(() => auth.currentUser).thenReturn(user);
        return user;
      }

      for (final (entitlements, paid) in <(Object?, bool)>[
        (['basic'], true),
        (['pro'], true),
        (['team', 'pro'], true),
        ([], false),
        (['team'], false),
        ('basic', false),
        ({'basic': true}, false),
        (null, false),
      ]) {
        test('gives $paid for the claim $entitlements', () async {
          userWithClaims({'revenueCatEntitlements': entitlements});

          expect(await identity().hasPaidEntitlement(), paid);
        });
      }

      test('gives false for a token without the claim, and for a token without claims', () async {
        userWithClaims({'sub': 'user-1'});
        expect(await identity().hasPaidEntitlement(), isFalse);

        userWithClaims(null);
        expect(await identity().hasPaidEntitlement(), isFalse);
      });

      test('starts Firebase and asks for a newly issued token at each call', () async {
        final user = userWithClaims({});
        final token = _MockIdTokenResult();
        when(() => token.claims).thenReturn({
          'revenueCatEntitlements': ['basic'],
        });
        // The starts of Firebase that came before each token. The answer only records them, because the adapter
        // catches every object, so an expectation inside the answer would not fail the test.
        final startsBeforeToken = <int>[];
        when(() => user.getIdTokenResult(any())).thenAnswer((_) async {
          startsBeforeToken.add(starts);
          return token;
        });
        final identity = FirebaseIdentity(initializeApp: initializeApp, auth: auth);

        expect(await identity.hasPaidEntitlement(), isTrue);
        expect(await identity.hasPaidEntitlement(), isTrue);

        // The token comes after the start, because Firebase Auth needs the app.
        expect(startsBeforeToken, [1, 2]);
        verify(() => user.getIdTokenResult(true)).called(2);
        verifyNever(() => auth.signInAnonymously());
      });

      test('gives false without an account, and never signs in', () async {
        expect(await identity().hasPaidEntitlement(), isFalse);

        expect(starts, 1);
        verifyNever(() => auth.signInAnonymously());
      });

      for (final (kind, failure) in <(String, Object)>[
        ('a missing network', FirebaseAuthException(code: 'network-request-failed')),
        ('a disabled account', FirebaseAuthException(code: 'user-disabled')),
        ('an error', StateError('no plugin')),
      ]) {
        test('gives false when the token fails with $kind', () async {
          final user = userWithId('user-1');
          when(() => user.getIdTokenResult(any())).thenAnswer((_) => Future.error(failure));
          when(() => auth.currentUser).thenReturn(user);

          expect(await identity().hasPaidEntitlement(), isFalse);
        });
      }

      test('gives false when Firebase does not start', () async {
        startFailures.add(Exception('no native config'));

        expect(await identity().hasPaidEntitlement(), isFalse);
        verifyZeroInteractions(auth);
      });

      test('waits for a sign-in that is on its way, and reads the token of the account that it makes', () async {
        final signIn = Completer<UserCredential>();
        final user = userWithId('user-1');
        final credential = credentialOf(user);
        final token = _MockIdTokenResult();
        when(() => token.claims).thenReturn({
          'revenueCatEntitlements': ['pro'],
        });
        when(() => user.getIdTokenResult(any())).thenAnswer((_) async => token);
        when(() => auth.signInAnonymously()).thenAnswer((_) => signIn.future);
        final identity = FirebaseIdentity(initializeApp: initializeApp, auth: auth);

        final startedAtLaunch = identity.currentUserId();
        await pumpEventQueue();
        final check = identity.hasPaidEntitlement();
        await pumpEventQueue();
        verifyNever(() => user.getIdTokenResult(any()));

        when(() => auth.currentUser).thenReturn(user);
        signIn.complete(credential);
        await startedAtLaunch;

        expect(await check, isTrue);
        verify(() => auth.signInAnonymously()).called(1);
      });
    });
  });
}
