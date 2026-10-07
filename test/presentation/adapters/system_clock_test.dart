// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/presentation/presentation.dart';

void main() {
  group('SystemClock', () {
    test('tells the time of the device', () {
      final before = DateTime.now();

      final now = const SystemClock().now();

      expect(now.isBefore(before), isFalse);
      expect(now.isAfter(DateTime.now()), isFalse);
    });
  });
}
