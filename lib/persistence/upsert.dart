import 'package:sqflite/sqflite.dart';

/// Updates the row of [table] that [where] selects, or inserts [key] and [values] as a new row when it selects none.
///
/// The function takes a [Transaction], because another write between the update and the insert could insert the
/// same row.
///
/// A plain update followed by a plain insert needs no SQLite feature that an old device can lack, and unlike
/// `INSERT OR REPLACE` it never overwrites a row that [where] does not select.
Future<void> upsert(
  Transaction transaction,
  String table, {
  required Map<String, Object?> key,
  required Map<String, Object?> values,
  required String where,
  required List<Object?> whereArgs,
}) async {
  final updated = await transaction.update(table, values, where: where, whereArgs: whereArgs);
  if (updated == 0) await transaction.insert(table, {...key, ...values});
}
