import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/upsert.dart';
import 'package:sqflite/sqflite.dart';

/// Stores the company profile as the one row of the `company_profile` table.
final class SqliteCompanyProfileRepository implements CompanyProfileRepository {
  const new(this._database);

  static const _rowId = 1;

  final Database _database;

  @override
  Future<CompanyProfile?> load() async {
    final rows = await _database.query('company_profile', where: 'id = ?', whereArgs: [_rowId]);
    return rows.isEmpty
        ? null
        : CompanyProfile(name: rows.single['name']! as String, phone: rows.single['phone']! as String);
  }

  @override
  Future<void> save(CompanyProfile profile) => _database.transaction(
    (transaction) => upsert(
      transaction,
      'company_profile',
      key: {'id': _rowId},
      values: {'name': profile.name, 'phone': profile.phone},
      where: 'id = ?',
      whereArgs: [_rowId],
    ),
  );
}
