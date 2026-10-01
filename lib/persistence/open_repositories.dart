import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/persistence/schema.dart';
import 'package:kkomkkomi/persistence/sqlite_client_repository.dart';
import 'package:kkomkkomi/persistence/sqlite_company_profile_repository.dart';
import 'package:kkomkkomi/persistence/sqlite_publish_repository.dart';
import 'package:kkomkkomi/persistence/sqlite_visit_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The name of the database file inside the databases directory of the platform.
const databaseFileName = 'kkomkkomi.db';

/// Opens the database at [path] with [factory], creates the schema when the file is new, and takes the schema of an
/// older file to [schemaVersion].
///
/// The connection enforces foreign keys.
Future<Database> openAppDatabase(DatabaseFactory factory, String path) => factory.openDatabase(
  path,
  options: OpenDatabaseOptions(
    version: schemaVersion,
    onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
    onCreate: (database, _) => createSchema(database),
    onUpgrade: (database, from, _) => upgradeSchema(database, from: from),
  ),
);

/// The repositories that read and write [database].
Repositories sqliteRepositories(Database database) => Repositories(
  clients: SqliteClientRepository(database),
  visits: SqliteVisitRepository(database),
  companyProfile: SqliteCompanyProfileRepository(database),
  publishing: SqlitePublishRepository(database),
);

/// Opens the database of this device with the default `sqflite` factory and returns its repositories.
///
/// The future completes with an error when the platform has no `sqflite` implementation or cannot open the file.
Future<Repositories> openDeviceRepositories() async {
  final factory = databaseFactory;
  final path = p.join(await factory.getDatabasesPath(), databaseFileName);
  return sqliteRepositories(await openAppDatabase(factory, path));
}
