import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  group('sameElements', () {
    test('is true for equal elements in the same order', () {
      expect(sameElements([1, 2], [1, 2]), isTrue);
      expect(sameElements(<int>[], <int>[]), isTrue);
    });

    test('is false for another length, another element, or another order', () {
      expect(sameElements([1, 2], [1]), isFalse);
      expect(sameElements([1, 2], [1, 3]), isFalse);
      expect(sameElements([1, 2], [2, 1]), isFalse);
    });
  });

  group('sameEntries', () {
    test('is true for the same keys with equal values, in any order', () {
      expect(sameEntries({'a': 1, 'b': 2}, {'b': 2, 'a': 1}), isTrue);
      expect(sameEntries(<String, int>{}, <String, int>{}), isTrue);
    });

    test('is false for another size, another key, or another value', () {
      expect(sameEntries({'a': 1}, {'a': 1, 'b': 2}), isFalse);
      expect(sameEntries({'a': 1}, {'b': 1}), isFalse);
      expect(sameEntries({'a': 1}, {'a': 2}), isFalse);
    });

    test('tells a null value from a key that is not there', () {
      expect(sameEntries<String, int?>({'a': null}, {'b': null}), isFalse);
      expect(sameEntries<String, int?>({'a': null}, {'a': null}), isTrue);
    });
  });
}
