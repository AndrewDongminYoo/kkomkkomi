// The domain imports only Dart core libraries, so `@immutable` from
// `package:meta` is not available here. Every field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// A calendar date without a time and without a time zone.
final class VisitDate implements Comparable<VisitDate> {
  /// Throws an [ArgumentError] when the three numbers do not name a calendar date.
  new(this.year, this.month, this.day) {
    final date = DateTime.utc(year, month, day);
    if (year < 1 || date.year != year || date.month != month || date.day != day) {
      throw ArgumentError('$year-$month-$day is not a calendar date');
    }
  }

  /// The calendar date that [dateTime] shows in its own time zone.
  factory fromDateTime(DateTime dateTime) => VisitDate(dateTime.year, dateTime.month, dateTime.day);

  final int year;
  final int month;
  final int day;

  @override
  int compareTo(VisitDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is VisitDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  /// The date in the `YYYY-MM-DD` form.
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
