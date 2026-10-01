import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/upsert.dart';
import 'package:sqflite/sqflite.dart';

/// Stores the visits and their zone records in the `visits` and `zone_records` tables.
final class SqliteVisitRepository implements VisitRepository {
  const new(this._database);

  final Database _database;

  @override
  Future<void> save(Visit visit) async {
    await _database.transaction((transaction) async {
      await upsert(
        transaction,
        'visits',
        key: {'id': visit.id},
        values: {
          'client_id': visit.clientId,
          'visit_date': _encodeDate(visit.visitDate),
          'created_at': visit.createdAt.microsecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [visit.id],
      );
      await transaction.delete('zone_records', where: 'visit_id = ?', whereArgs: [visit.id]);
      // The foreign key of a record checks only that its zone exists, so the zones of the client are read here.
      final zones = await transaction.query(
        'zones',
        columns: ['id'],
        where: 'client_id = ?',
        whereArgs: [visit.clientId],
      );
      final zoneIds = {for (final zone in zones) zone['id']};
      for (final (position, record) in visit.zoneRecords.indexed) {
        if (!zoneIds.contains(record.zoneId)) {
          throw ArgumentError.value(record.zoneId, 'visit', 'The client of the visit has no such zone');
        }
        await transaction.insert('zone_records', {
          'visit_id': visit.id,
          'zone_id': record.zoneId,
          'position': position,
          'zone_name': record.zoneName,
          'before_photo': record.beforePhoto?.path,
          'after_photo': record.afterPhoto?.path,
          'note': record.note,
        });
      }
    });
  }

  // A visit and its zone records come from two statements. Each read runs in one transaction, so that a save between
  // the statements cannot mix the visit of one state with the records of another.
  @override
  Future<Visit?> visitById(String id) => _database.transaction((transaction) async {
    final rows = await transaction.query('visits', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : await _visitFromRow(transaction, rows.single);
  });

  @override
  Future<List<Visit>> visitsOf(String clientId) => _database.transaction((transaction) async {
    final rows = await transaction.query(
      'visits',
      where: 'client_id = ?',
      whereArgs: [clientId],
      orderBy: 'visit_date DESC, created_at DESC, id',
    );
    return [for (final row in rows) await _visitFromRow(transaction, row)];
  });

  static Future<Visit> _visitFromRow(DatabaseExecutor database, Map<String, Object?> row) async {
    final id = row['id']! as String;
    final records = await database.query('zone_records', where: 'visit_id = ?', whereArgs: [id], orderBy: 'position');
    return Visit(
      id: id,
      clientId: row['client_id']! as String,
      visitDate: _decodeDate(row['visit_date']! as int),
      createdAt: DateTime.fromMicrosecondsSinceEpoch(row['created_at']! as int, isUtc: true),
      zoneRecords: records.map(_recordFromRow),
    );
  }

  static ZoneRecord _recordFromRow(Map<String, Object?> row) => ZoneRecord(
    zoneId: row['zone_id']! as String,
    zoneName: row['zone_name']! as String,
    beforePhoto: _photoFrom(row['before_photo']),
    afterPhoto: _photoFrom(row['after_photo']),
    note: row['note']! as String,
  );

  static PhotoRef? _photoFrom(Object? path) => path == null ? null : PhotoRef(path as String);

  static int _encodeDate(VisitDate date) => date.year * 10000 + date.month * 100 + date.day;

  static VisitDate _decodeDate(int date) => VisitDate(date ~/ 10000, date ~/ 100 % 100, date % 100);
}
