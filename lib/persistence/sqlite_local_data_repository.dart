// 📦 Package imports:
import 'package:sqflite/sqflite.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';

/// Erases every table of the database of the app.
final class SqliteLocalDataRepository implements LocalDataRepository {
  const new(this._database);

  final Database _database;

  /// The tables of the schema, each after the tables whose rows refer to its rows, so that no delete breaks a foreign
  /// key.
  static const tables = [
    'open_capture',
    'published_photos',
    'publish_jobs',
    'client_pages',
    'zone_records',
    'visits',
    'zones',
    'clients',
    'company_profile',
  ];

  @override
  Future<void> eraseAll() async {
    await _database.transaction((transaction) async {
      for (final table in tables) {
        await transaction.delete(table);
      }
    });
    // A delete marks the pages of the file as free and leaves their bytes. VACUUM writes the file again without them,
    // and the checkpoint empties a write-ahead log that may hold them, when the platform keeps one.
    await _database.execute('VACUUM');
    await _database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  }
}
