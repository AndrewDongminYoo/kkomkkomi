import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

void main() {
  group('RandomIdGenerator', () {
    test('writes 16 bytes of the random source as 32 hexadecimal digits', () {
      final expected = Random(7);
      final bytes = [for (var byte = 0; byte < 16; byte++) expected.nextInt(256)];

      final id = RandomIdGenerator(random: Random(7)).newId();

      expect(id, bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join());
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('makes a new identifier on each call when no random source is given', () {
      const generator = RandomIdGenerator();

      final ids = {for (var count = 0; count < 100; count++) generator.newId()};

      expect(ids, hasLength(100));
      expect(ids, everyElement(matches(RegExp(r'^[0-9a-f]{32}$'))));
    });
  });
}
