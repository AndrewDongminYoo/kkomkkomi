import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/upsert.dart';
import 'package:sqflite/sqflite.dart';

/// Stores the capture that has the camera open as the one row of the `open_capture` table.
///
/// The slot is stored as the name of its [PhotoSlot] value.
final class SqliteOpenCaptureRepository implements OpenCaptureRepository {
  const new(this._database);

  static const _table = 'open_capture';
  static const _rowId = 1;

  final Database _database;

  @override
  Future<OpenCapture?> load() async {
    final rows = await _database.query(_table, where: 'id = ?', whereArgs: [_rowId]);
    if (rows.isEmpty) return null;
    final row = rows.single;
    return OpenCapture(
      visitId: row['visit_id']! as String,
      zoneId: row['zone_id']! as String,
      slot: PhotoSlot.values.byName(row['slot']! as String),
      source: PhotoSource.values.asNameMap()[row['source']] ?? PhotoSource.unknown,
    );
  }

  @override
  Future<void> save(OpenCapture capture) => _database.transaction(
    (transaction) => upsert(
      transaction,
      _table,
      key: {'id': _rowId},
      values: {
        'visit_id': capture.visitId,
        'zone_id': capture.zoneId,
        'slot': capture.slot.name,
        'source': capture.source.name,
      },
      where: 'id = ?',
      whereArgs: [_rowId],
    ),
  );

  @override
  Future<void> clear() => _database.delete(_table, where: 'id = ?', whereArgs: [_rowId]);
}
