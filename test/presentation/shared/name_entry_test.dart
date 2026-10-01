import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

void main() {
  group('NameEntry.refusedBy', () {
    test('names an empty name', () {
      expect(NameEntry.refusedBy(const EmptyNameException()), NameEntry.empty);
    });

    test('names a duplicate zone name', () {
      expect(NameEntry.refusedBy(const DuplicateZoneNameException('로비')), NameEntry.duplicate);
    });
  });
}
