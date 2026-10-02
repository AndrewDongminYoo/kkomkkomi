import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/persistence.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('kkomkkomi_test_');
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  group('openAppDatabase', () {
    test('creates the version 3 schema with one table for each entity, the tables of publishing, and the open '
        'capture', () async {
      final database = await openMemoryDatabase();
      addTearDown(database.close);

      final tables = await database.query('sqlite_master', columns: ['name'], where: "type = 'table'", orderBy: 'name');

      expect(tables.map((row) => row['name']), [
        'client_pages',
        'clients',
        'company_profile',
        'open_capture',
        'publish_jobs',
        'published_photos',
        'visits',
        'zone_records',
        'zones',
      ]);
      expect(await database.getVersion(), schemaVersion);
      expect(schemaVersion, 3);
    });

    test('takes a version 1 file to the current version and keeps its data', () async {
      final path = p.join(directory.path, databaseFileName);
      final client = Client(id: 'client-1', name: '한빛 사무실', createdAt: DateTime.utc(2026, 9));
      final old = await testDatabaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (database, _) => upgradeSchema(database, from: 0, to: 1),
        ),
      );
      await sqliteRepositories(old).clients.save(client);
      expect(
        await old.query('sqlite_master', where: "type = 'table' AND name = ?", whereArgs: ['publish_jobs']),
        isEmpty,
      );
      await old.close();

      final upgraded = await openAppDatabase(testDatabaseFactory, path);
      addTearDown(upgraded.close);
      final repositories = sqliteRepositories(upgraded);
      final page = ClientPage(id: 'page-1', clientId: 'client-1', createdAt: DateTime.utc(2026, 10));

      expect(await upgraded.getVersion(), schemaVersion);
      expect(await repositories.clients.clientById('client-1'), client);
      expect(await repositories.publishing.openPageOf('client-1', create: () => page), page);
      expect(await repositories.publishing.pendingJobs(), isEmpty);
      // The new tables carry the generation of a job and whether an upload arrived.
      final job = PublishJob(id: 'job-1', kind: PublishJobKind.revoke, pageId: 'page-1', createdAt: DateTime.utc(2026));
      await repositories.publishing.enqueue(job);
      expect(await repositories.publishing.saveJob(job.succeed()), isTrue);
      await repositories.publishing.recordUploadIntent(pageId: 'page-1', objectPath: 'a.jpg', photoPath: 'p/1.jpg');
      expect(await repositories.publishing.uploadedObjects('page-1'), ['a.jpg']);
      expect(await repositories.publishing.uploadedPhoto(pageId: 'page-1', objectPath: 'a.jpg'), isNull);
    });

    test('takes a version 2 file to version 3, keeps its data, and stores an open capture', () async {
      final path = p.join(directory.path, databaseFileName);
      final client = Client(id: 'client-1', name: '한빛 사무실', createdAt: DateTime.utc(2026, 9));
      final zones = ClientZones(
        clientId: 'client-1',
        zones: [Zone(id: 'zone-1', clientId: 'client-1', name: '로비', position: 0)],
      );
      final visit = Visit(
        id: 'visit-1',
        clientId: 'client-1',
        visitDate: VisitDate(2026, 10, 2),
        createdAt: DateTime.utc(2026, 10, 2, 9),
        zoneRecords: [ZoneRecord(zoneId: 'zone-1', zoneName: '로비', beforePhoto: PhotoRef('photos/visit-1/b.jpg'))],
      );
      final page = ClientPage(id: 'page-1', clientId: 'client-1', createdAt: DateTime.utc(2026, 10));
      final old = await testDatabaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
          onCreate: (database, _) => upgradeSchema(database, from: 0, to: 2),
        ),
      );
      final written = sqliteRepositories(old);
      await written.clients.save(client, zones: zones);
      await written.visits.save(visit);
      await written.publishing.openPageOf('client-1', create: () => page);
      expect(
        await old.query('sqlite_master', where: "type = 'table' AND name = ?", whereArgs: ['open_capture']),
        isEmpty,
      );
      await old.close();

      final upgraded = await openAppDatabase(testDatabaseFactory, path);
      addTearDown(upgraded.close);
      final repositories = sqliteRepositories(upgraded);
      const capture = OpenCapture(visitId: 'visit-1', zoneId: 'zone-1', slot: PhotoSlot.after);

      expect(await upgraded.getVersion(), 3);
      expect(await repositories.clients.clientById('client-1'), client);
      expect(await repositories.clients.zonesOf('client-1'), zones);
      expect(await repositories.visits.visitById('visit-1'), visit);
      expect(await repositories.publishing.openPageOf('client-1', create: () => throw StateError('new page')), page);
      expect(await repositories.openCaptures.load(), isNull);
      await repositories.openCaptures.save(capture);
      expect(await repositories.openCaptures.load(), capture);
    });

    test('enforces foreign keys', () async {
      final database = await openMemoryDatabase();
      addTearDown(database.close);

      expect(await database.rawQuery('PRAGMA foreign_keys'), [
        {'foreign_keys': 1},
      ]);
      await expectLater(
        database.insert('zones', {
          'id': 'zone-1',
          'client_id': 'client-9',
          'name': '로비',
          'position': 0,
          'is_active': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('reads the stored data again after the database file is closed and reopened', () async {
      final path = p.join(directory.path, 'nested', databaseFileName);
      final client = Client(id: 'client-1', name: '한빛 사무실', createdAt: DateTime.utc(2026, 9));
      final zones = ClientZones(
        clientId: 'client-1',
        zones: [Zone(id: 'zone-1', clientId: 'client-1', name: '로비', position: 0)],
      );
      final visit = Visit(
        id: 'visit-1',
        clientId: 'client-1',
        visitDate: VisitDate(2026, 10, 1),
        createdAt: DateTime.utc(2026, 10, 1, 9),
        zoneRecords: [
          ZoneRecord(zoneId: 'zone-1', zoneName: '로비', afterPhoto: PhotoRef('photos/visit-1/after.jpg'), note: '메모'),
        ],
      );
      final profile = CompanyProfile(name: '반짝 클린');

      final first = await openAppDatabase(testDatabaseFactory, path);
      final written = sqliteRepositories(first);
      await written.clients.save(client, zones: zones);
      await written.visits.save(visit);
      await written.companyProfile.save(profile);
      await first.close();

      final second = await openAppDatabase(testDatabaseFactory, path);
      addTearDown(second.close);
      final read = sqliteRepositories(second);

      expect(File(path).existsSync(), isTrue);
      expect(await read.clients.clientById('client-1'), client);
      expect(await read.clients.zonesOf('client-1'), zones);
      expect(await read.visits.visitById('visit-1'), visit);
      expect(await read.companyProfile.load(), profile);
    });
  });

  group('openDeviceRepositories', () {
    test('opens the database file in the databases directory of the default factory', () async {
      final factory = createDatabaseFactoryFfi(noIsolate: true);
      await factory.setDatabasesPath(directory.path);
      final previous = databaseFactoryOrNull;
      databaseFactoryOrNull = factory;
      addTearDown(() => databaseFactoryOrNull = previous);

      final repositories = await openDeviceRepositories();
      await repositories.companyProfile.save(CompanyProfile(name: '반짝 클린'));

      // The path is open as a single instance, so this call returns the database that the repositories use.
      final path = p.join(directory.path, databaseFileName);
      final database = await factory.openDatabase(path);
      addTearDown(database.close);
      expect(File(path).existsSync(), isTrue);
      expect(await database.query('company_profile'), [
        {'id': 1, 'name': '반짝 클린'},
      ]);
    });

    test('fails when the default factory cannot open the file', () async {
      final blocked = File(p.join(directory.path, 'blocked'))..writeAsStringSync('not a directory');
      final factory = createDatabaseFactoryFfi(noIsolate: true);
      await factory.setDatabasesPath(blocked.path);
      final previous = databaseFactoryOrNull;
      databaseFactoryOrNull = factory;
      addTearDown(() => databaseFactoryOrNull = previous);

      await expectLater(openDeviceRepositories(), throwsA(anything));
    });
  });
}
