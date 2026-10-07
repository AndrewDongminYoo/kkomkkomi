// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/persistence.dart';

import 'support.dart';

void main() {
  late Database database;
  late SqliteCompanyProfileRepository repository;

  setUp(() async {
    database = await openMemoryDatabase();
    repository = SqliteCompanyProfileRepository(database);
  });

  tearDown(() => database.close());

  group('SqliteCompanyProfileRepository', () {
    test('round-trips and clears the optional phone without another profile row', () async {
      final profile = CompanyProfile(name: '반짝 클린', phone: '02-1234-5678');
      await repository.save(profile);
      expect(await repository.load(), profile);
      await repository.save(CompanyProfile(name: profile.name));
      expect((await repository.load())!.phone, isEmpty);
      expect(await database.query('company_profile'), hasLength(1));
    });
    test('loads null before a profile is saved', () async {
      expect(await repository.load(), isNull);
    });

    test('round-trips the profile', () async {
      await repository.save(CompanyProfile(name: '반짝 클린'));

      expect(await repository.load(), CompanyProfile(name: '반짝 클린'));
    });

    test('saves a changed profile over the stored one', () async {
      await repository.save(CompanyProfile(name: '반짝 클린'));

      await repository.save(CompanyProfile(name: '새 이름'));

      expect(await repository.load(), CompanyProfile(name: '새 이름'));
      expect(await database.query('company_profile'), hasLength(1));
    });

    test('keeps the later of two first saves that run at the same time', () async {
      await Future.wait([
        repository.save(CompanyProfile(name: '먼저 저장')),
        repository.save(CompanyProfile(name: '나중 저장')),
      ]);

      expect(await repository.load(), CompanyProfile(name: '나중 저장'));
      expect(await database.query('company_profile'), hasLength(1));
    });
  });
}
