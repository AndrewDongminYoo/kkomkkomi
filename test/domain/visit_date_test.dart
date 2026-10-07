// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  group('VisitDate', () {
    test('holds a year, a month, and a day', () {
      final date = VisitDate(2026, 10, 1);

      expect((date.year, date.month, date.day), (2026, 10, 1));
    });

    test('accepts the last day of February in a leap year', () {
      expect(VisitDate(2028, 2, 29).day, 29);
    });

    test('refuses numbers that do not name a calendar date', () {
      expect(() => VisitDate(2026, 2, 29), throwsArgumentError);
      expect(() => VisitDate(2026, 13, 1), throwsArgumentError);
      expect(() => VisitDate(2026, 0, 10), throwsArgumentError);
      expect(() => VisitDate(2026, 10, 0), throwsArgumentError);
      expect(() => VisitDate(0, 10, 1), throwsArgumentError);
    });

    test('fromDateTime takes the date that the time shows and drops the time', () {
      expect(VisitDate.fromDateTime(DateTime(2026, 10, 1, 23, 59)), VisitDate(2026, 10, 1));
      expect(VisitDate.fromDateTime(DateTime.utc(2026, 12, 31, 0, 0, 1)), VisitDate(2026, 12, 31));
    });

    test('orders dates by year, then month, then day', () {
      expect(VisitDate(2026, 10, 1).compareTo(VisitDate(2027, 1, 1)), isNegative);
      expect(VisitDate(2026, 10, 1).compareTo(VisitDate(2026, 9, 30)), isPositive);
      expect(VisitDate(2026, 10, 1).compareTo(VisitDate(2026, 10, 2)), isNegative);
      expect(VisitDate(2026, 10, 1).compareTo(VisitDate(2026, 10, 1)), isZero);
    });

    test('is equal to the same calendar date', () {
      expect(VisitDate(2026, 10, 1), VisitDate(2026, 10, 1));
      expect(VisitDate(2026, 10, 1).hashCode, VisitDate(2026, 10, 1).hashCode);
      expect(VisitDate(2026, 10, 1), isNot(VisitDate(2025, 10, 1)));
      expect(VisitDate(2026, 10, 1), isNot(VisitDate(2026, 11, 1)));
      expect(VisitDate(2026, 10, 1), isNot(VisitDate(2026, 10, 2)));
    });

    test('prints the YYYY-MM-DD form', () {
      expect(VisitDate(2026, 3, 7).toString(), '2026-03-07');
      expect(VisitDate(987, 12, 31).toString(), '0987-12-31');
    });
  });
}
