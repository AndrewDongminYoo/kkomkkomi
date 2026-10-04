import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

void main() {
  group('UnavailableIdentity', () {
    test('is an identity that gives no user ID, at each call', () async {
      const Identity identity = UnavailableIdentity();

      expect(await identity.currentUserId(), isNull);
      expect(await identity.currentUserId(), isNull);
    });

    test('deletes no account, because it holds none', () async {
      const Identity identity = UnavailableIdentity();

      await expectLater(identity.deleteAccount(), completes);
      expect(await identity.currentUserId(), isNull);
    });

    test('holds no paid entitlement, because it holds no account', () async {
      const Identity identity = UnavailableIdentity();

      expect(await identity.hasPaidEntitlement(), isFalse);
    });
  });
}
