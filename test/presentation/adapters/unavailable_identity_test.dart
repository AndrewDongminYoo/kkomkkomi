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
  });
}
