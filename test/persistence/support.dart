// 📦 Package imports:
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/persistence/persistence.dart';

/// The factory that the persistence tests use: SQLite through FFI, on the isolate of the test.
DatabaseFactory get testDatabaseFactory => databaseFactoryFfiNoIsolate;

/// Opens a new in-memory database with the schema of the app.
Future<Database> openMemoryDatabase() => openAppDatabase(testDatabaseFactory, inMemoryDatabasePath);
