import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/persistence.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

/// Fails only a post-commit cleanup operation while the transaction uses real SQLite.
class _PostCommitFailureDatabase extends Mock implements Database {
  new(this.inner, this.statement);
  final Database inner;
  final String statement;

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction) action, {bool? exclusive}) =>
      inner.transaction(action, exclusive: exclusive);

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (sql == statement) throw StateError('Post-commit cleanup failed');
    await inner.execute(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql == statement) throw StateError('Post-commit cleanup failed');
    return inner.rawQuery(sql, arguments);
  }
}

void main() {
  late Directory directory;
  late String path;
  late Database database;

  /// A text that only the rows of the test hold, so that a test can look for it in the bytes of the file.
  const marker = 'KKOMKKOMI-ERASE-MARKER';

  /// Fills each table of the schema with at least one row.
  Future<void> fill(Repositories repositories) async {
    await repositories.companyProfile.save(CompanyProfile(name: '$marker 청소'));
    await repositories.clients.save(
      Client(id: 'client-1', name: '$marker 상가', createdAt: DateTime.utc(2026, 9)),
      zones: ClientZones(
        clientId: 'client-1',
        zones: [Zone(id: 'zone-1', clientId: 'client-1', name: '입구', position: 0)],
      ),
    );
    final photo = PhotoRef('photos/visit-1/photo-1.jpg');
    await repositories.visits.save(
      Visit(
        id: 'visit-1',
        clientId: 'client-1',
        visitDate: VisitDate(2026, 10, 2),
        createdAt: DateTime.utc(2026, 10, 2),
        zoneRecords: [ZoneRecord(zoneId: 'zone-1', zoneName: '입구', beforePhoto: photo, note: '$marker 메모')],
      ),
    );
    final page = (await repositories.publishing.openPageOf(
      'client-1',
      create: () => ClientPage(id: 'page-1', clientId: 'client-1', createdAt: DateTime.utc(2026, 10, 2)),
    ))!;
    await repositories.publishing.enqueue(
      PublishJob(
        id: 'job-1',
        kind: PublishJobKind.publish,
        pageId: page.id,
        visitId: 'visit-1',
        createdAt: DateTime.utc(2026, 10, 2),
      ),
    );
    await repositories.publishing.saveUploadedPhoto(
      pageId: page.id,
      objectPath: 'clientPages/page-1/visit-1/zone-1-before-photo-1.jpg',
      photoPath: photo.path,
    );
    await repositories.openCaptures.save(
      const OpenCapture(visitId: 'visit-1', zoneId: 'zone-1', slot: PhotoSlot.before),
    );
  }

  Future<Map<String, int>> rowCounts() async => {
    for (final table in SqliteLocalDataRepository.tables)
      table: (await database.rawQuery('SELECT COUNT(*) AS count FROM $table')).single['count']! as int,
  };

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('sqlite_local_data_repository_test');
    path = '${directory.path}/app.db';
    database = await openAppDatabase(testDatabaseFactory, path);
  });

  tearDown(() async {
    await database.close();
    directory.deleteSync(recursive: true);
  });

  group('SqliteLocalDataRepository', () {
    test('names every table of the schema', () async {
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
      );

      expect(SqliteLocalDataRepository.tables.toSet(), {for (final row in tables) row['name']! as String});
    });

    test('deletes every row of every table, and the app then reads the state of a first launch', () async {
      final repositories = sqliteRepositories(database);
      await fill(repositories);
      expect((await rowCounts()).values, everyElement(greaterThan(0)));

      await repositories.localData.eraseAll();

      expect((await rowCounts()).values, everyElement(0));
      expect(await repositories.companyProfile.load(), isNull);
      expect(await repositories.clients.activeClients(), isEmpty);
      expect(await repositories.publishing.pages(), isEmpty);
      expect(await repositories.openCaptures.load(), isNull);
      // The schema stays, so the app goes on with the same database.
      await repositories.clients.save(Client(id: 'client-2', name: '새 거래처', createdAt: DateTime.utc(2026, 10)));
      expect(await repositories.clients.activeClients(), hasLength(1));
    });

    test('leaves no deleted text in the database file', () async {
      final repositories = sqliteRepositories(database);
      await fill(repositories);
      await database.close();
      expect(String.fromCharCodes(File(path).readAsBytesSync()).contains(marker), isTrue);
      database = await openAppDatabase(testDatabaseFactory, path);

      await sqliteRepositories(database).localData.eraseAll();
      await database.close();

      expect(String.fromCharCodes(File(path).readAsBytesSync()).contains(marker), isFalse);
      database = await openAppDatabase(testDatabaseFactory, path);
    });

    test('is safe to repeat', () async {
      final repositories = sqliteRepositories(database);

      await repositories.localData.eraseAll();
      await repositories.localData.eraseAll();

      expect((await rowCounts()).values, everyElement(0));
    });

    for (final statement in ['VACUUM', 'PRAGMA wal_checkpoint(TRUNCATE)']) {
      test('rows are erased before a $statement failure', () async {
        await fill(sqliteRepositories(database));
        final repository = SqliteLocalDataRepository(_PostCommitFailureDatabase(database, statement));
        await expectLater(repository.eraseAll(), throwsStateError);
        expect((await rowCounts()).values, everyElement(0));
        await database.close();
        database = await openAppDatabase(testDatabaseFactory, path);
        expect((await rowCounts()).values, everyElement(0));
        await sqliteRepositories(database).localData.eraseAll();
      });
    }

    test('keeps every row when the erase fails', () async {
      final repositories = sqliteRepositories(database);
      await fill(repositories);
      final before = await rowCounts();
      // A trigger that refuses the delete of the last table makes the transaction fail after the others.
      await database.execute(
        "CREATE TRIGGER refuse BEFORE DELETE ON company_profile BEGIN SELECT RAISE(ABORT, 'refused'); END",
      );

      await expectLater(repositories.localData.eraseAll(), throwsA(isA<DatabaseException>()));

      expect(await rowCounts(), before);
    });
  });
}
