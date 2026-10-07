// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

import '../../../helpers/helpers.dart';

void main() {
  final profile = CompanyProfile(name: '반짝 클린');
  final failure = Exception('storage failed');

  late MockCompanyProfileRepository companyProfile;
  late FakeLocalDataRepository localData;
  late FakePhotoStore photoStore;
  late PublishQueue publishQueue;

  CompanyProfileCubit build() => CompanyProfileCubit(
    companyProfile: companyProfile,
    // A queue without a backend, so the deletion deletes the data on the device only.
    deleteAllData: DeleteAllData(
      publishQueue: publishQueue,
      identity: FakeIdentity(),
      localData: localData,
      photoStore: photoStore,
    ),
  );

  CompanyProfileState ready({String name = '', NameEntry entry = NameEntry.editing}) =>
      CompanyProfileState(status: CompanyProfileStatus.ready, name: name, entry: entry);

  setUpAll(() => registerFallbackValue(profile));

  setUp(() {
    companyProfile = MockCompanyProfileRepository();
    when(() => companyProfile.save(any())).thenAnswer((_) async {});
    localData = FakeLocalDataRepository();
    photoStore = FakePhotoStore();
    publishQueue = publishQueueOf(mockRepositories());
  });

  tearDown(() => publishQueue.dispose());

  for (final step in [DeletionStep.account, DeletionStep.deviceData]) {
    test('page confirmation keeps Company profile failure at ${step.name}', () async {
      final publishing = FakePublishRepository();
      final page = ClientPage(id: 'page', clientId: 'client', createdAt: DateTime.utc(2026));
      publishing.pagesById[page.id] = page;
      final backend = FakePublisher();
      final identity = FakeIdentity(userId: 'owner');
      if (step == DeletionStep.account) identity.deleteFailures.add(failure);
      if (step == DeletionStep.deviceData) photoStore.deleteAllFailure = failure;
      localData.onErase = () {
        publishing.pagesById.clear();
        publishing.jobs.clear();
      };
      final queue = publishQueueOf(
        Repositories(
          clients: FakeClientRepository(),
          visits: FakeVisitRepository(),
          companyProfile: FakeCompanyProfileRepository(),
          publishing: publishing,
          openCaptures: FakeOpenCaptureRepository(),
          localData: localData,
        ),
        publisher: backend,
      );
      final cubit = CompanyProfileCubit(
        companyProfile: companyProfile,
        deleteAllData: DeleteAllData(
          publishQueue: queue,
          identity: identity,
          localData: localData,
          photoStore: photoStore,
        ),
      );
      await cubit.deleteAllData();
      expect(cubit.state.deletionFailure, step);
      if (step == DeletionStep.account) expect(publishing.pagesById[page.id]!.serverDeletedAt, isNotNull);
      if (step == DeletionStep.deviceData) expect(publishing.pagesById, isEmpty);
      await cubit.close();
      await queue.dispose();
    });
  }

  group('CompanyProfileState', () {
    test('keeps the phone across deletion and entry states', () {
      final state = ready(name: '반짝 클린').copyWith(phone: '02-1234-5678');
      expect(state.withDeletion(DataDeletion.deleting).phone, state.phone);
      expect(state.copyWith(entry: NameEntry.saving).phone, state.phone);
      expect(state, isNot(ready(name: '반짝 클린')));
      expect(state.hashCode, ready(name: '반짝 클린').copyWith(phone: '02-1234-5678').hashCode);
    });
    test('is equal to a state with the same fields', () {
      expect(ready(name: '반짝 클린'), ready(name: '반짝 클린'));
      expect(ready(name: '반짝 클린').hashCode, ready(name: '반짝 클린').hashCode);
      expect(
        ready().withDeletion(DataDeletion.idle, failure: DeletionStep.account),
        ready().withDeletion(DataDeletion.idle, failure: DeletionStep.account),
      );
    });

    test('differs from a state with another field value', () {
      expect(ready(), isNot(const CompanyProfileState()));
      expect(ready(), isNot(ready(name: '반짝 클린')));
      expect(ready(), isNot(ready(entry: NameEntry.saved)));
      expect(ready(), isNot(ready().withDeletion(DataDeletion.deleting)));
      expect(ready(), isNot(ready().withDeletion(DataDeletion.idle, failure: DeletionStep.deviceData)));
    });

    test('keeps the deletion through a change of the name', () {
      final deleting = ready().withDeletion(DataDeletion.idle, failure: DeletionStep.account);

      expect(deleting.copyWith(entry: NameEntry.saving).deletionFailure, DeletionStep.account);
      expect(deleting.copyWith(entry: NameEntry.saving).entry, NameEntry.saving);
      expect(deleting.copyWith(), deleting);
    });
  });

  group('CompanyProfileCubit', () {
    test('starts without a name while the first load runs', () {
      expect(build().state, const CompanyProfileState());
      expect(build().state.status, CompanyProfileStatus.loading);
    });

    group('load', () {
      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'shows the saved company name',
        setUp: () => when(companyProfile.load).thenAnswer((_) async => profile),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [ready(name: '반짝 클린')],
      );

      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'shows an empty name when no profile was saved',
        setUp: () => when(companyProfile.load).thenAnswer((_) async => null),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [ready()],
      );

      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'reports a failure of storage',
        setUp: () => when(companyProfile.load).thenThrow(failure),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [const CompanyProfileState(status: CompanyProfileStatus.loadFailed)],
        errors: () => [failure],
      );

      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'shows the loading state and then the name when it runs again after a failure',
        setUp: () => when(companyProfile.load).thenAnswer((_) async => profile),
        build: build,
        seed: () => const CompanyProfileState(status: CompanyProfileStatus.loadFailed),
        act: (cubit) => cubit.load(),
        expect: () => [const CompanyProfileState(), ready(name: '반짝 클린')],
      );

      for (final (description, answerLoad) in <(String, void Function(Completer<CompanyProfile?>))>[
        ('storage answers', (answer) => answer.complete(profile)),
        ('storage fails', (answer) => answer.completeError(failure)),
      ]) {
        test('emits nothing when the cubit closes before $description', () async {
          final answer = Completer<CompanyProfile?>();
          when(companyProfile.load).thenAnswer((_) => answer.future);
          final cubit = build();

          final load = cubit.load();
          await cubit.close();
          answerLoad(answer);
          await load;

          expect(cubit.state, const CompanyProfileState());
        });
      }
    });

    group('save', () {
      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'saves the phone with the name and can clear it',
        build: build,
        seed: ready,
        act: (cubit) async {
          await cubit.save('반짝 클린', phone: ' 02-1234-5678 ');
          await cubit.save('반짝 클린');
        },
        expect: () => [
          ready(entry: NameEntry.saving),
          ready(name: '반짝 클린', entry: NameEntry.saved).copyWith(phone: '02-1234-5678'),
          ready(name: '반짝 클린', entry: NameEntry.saving).copyWith(phone: '02-1234-5678'),
          ready(name: '반짝 클린', entry: NameEntry.saved),
        ],
      );
      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'saves the trimmed name and shows it as the saved name',
        build: build,
        seed: ready,
        act: (cubit) => cubit.save('  반짝 클린 '),
        expect: () => [
          ready(entry: NameEntry.saving),
          ready(name: '반짝 클린', entry: NameEntry.saved),
        ],
        verify: (_) => verify(() => companyProfile.save(profile)).called(1),
      );

      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'refuses an empty name and saves nothing',
        build: build,
        seed: () => ready(name: '반짝 클린'),
        act: (cubit) => cubit.save(' '),
        expect: () => [ready(name: '반짝 클린', entry: NameEntry.empty)],
        verify: (_) => verifyNever(() => companyProfile.save(any())),
      );

      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'reports a failure of storage and keeps the saved name',
        setUp: () => when(() => companyProfile.save(any())).thenThrow(failure),
        build: build,
        seed: () => ready(name: '반짝 클린'),
        act: (cubit) => cubit.save('새 이름'),
        expect: () => [
          ready(name: '반짝 클린', entry: NameEntry.saving),
          ready(name: '반짝 클린', entry: NameEntry.failed),
        ],
        errors: () => [failure],
      );

      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'saves again after a saved name, so that the form can report each save',
        build: build,
        seed: () => ready(name: '반짝 클린', entry: NameEntry.saved),
        act: (cubit) => cubit.save('반짝 클린'),
        expect: () => [
          ready(name: '반짝 클린', entry: NameEntry.saving),
          ready(name: '반짝 클린', entry: NameEntry.saved),
        ],
      );

      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'takes no second name while the first is on its way to storage',
        build: build,
        seed: ready,
        act: (cubit) async {
          final first = cubit.save('반짝 클린');
          await cubit.save('두 번째');
          await first;
        },
        expect: () => [
          ready(entry: NameEntry.saving),
          ready(name: '반짝 클린', entry: NameEntry.saved),
        ],
        verify: (_) => verify(() => companyProfile.save(any())).called(1),
      );

      for (final (description, answerSave) in <(String, void Function(Completer<void>))>[
        ('storage answers', (answer) => answer.complete()),
        ('storage fails', (answer) => answer.completeError(failure)),
      ]) {
        test('emits nothing more when the cubit closes before $description', () async {
          final answer = Completer<void>();
          when(() => companyProfile.save(any())).thenAnswer((_) => answer.future);
          final cubit = build();

          final save = cubit.save('반짝 클린');
          await cubit.close();
          answerSave(answer);
          await save;

          expect(cubit.state.entry, NameEntry.saving);
        });
      }
    });

    group('deleteAllData', () {
      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'deletes all data and reports that it did',
        build: build,
        seed: () => ready(name: '반짝 클린'),
        act: (cubit) => cubit.deleteAllData(),
        expect: () => [
          ready(name: '반짝 클린').withDeletion(DataDeletion.deleting),
          ready(name: '반짝 클린').withDeletion(DataDeletion.deleted),
        ],
        verify: (_) {
          expect(localData.erasures, 1);
          expect(photoStore.deletionsOfAll, 1);
        },
      );

      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'names the step at which the deletion stopped, and clears it at the next try',
        setUp: () => localData.failure = Exception('disk I/O error'),
        build: build,
        seed: ready,
        act: (cubit) async {
          await cubit.deleteAllData();
          localData.failure = null;
          await cubit.deleteAllData();
        },
        expect: () => [
          ready().withDeletion(DataDeletion.deleting),
          ready().withDeletion(DataDeletion.idle, failure: DeletionStep.deviceData),
          ready().withDeletion(DataDeletion.deleting),
          ready().withDeletion(DataDeletion.deleted),
        ],
        errors: () => [isA<DeletionFailure>()],
      );

      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'takes no second deletion while the first is on its way',
        setUp: () => localData.gate = Completer<void>(),
        build: build,
        seed: ready,
        act: (cubit) async {
          final first = cubit.deleteAllData();
          await cubit.deleteAllData();
          localData.gate!.complete();
          await first;
        },
        expect: () => [ready().withDeletion(DataDeletion.deleting), ready().withDeletion(DataDeletion.deleted)],
        verify: (_) => expect(localData.erasures, 1),
      );

      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'saves no name while a deletion is on its way or after it completed',
        setUp: () => localData.gate = Completer<void>(),
        build: build,
        seed: ready,
        act: (cubit) async {
          final deletion = cubit.deleteAllData();
          await cubit.save('반짝 클린');
          localData.gate!.complete();
          await deletion;
          await cubit.save('반짝 클린');
        },
        expect: () => [ready().withDeletion(DataDeletion.deleting), ready().withDeletion(DataDeletion.deleted)],
        verify: (_) => verifyNever(() => companyProfile.save(any())),
      );

      blocTest<CompanyProfileCubit, CompanyProfileState>(
        'starts no deletion while a name is on its way to storage',
        build: build,
        seed: () => ready(entry: NameEntry.saving),
        act: (cubit) => cubit.deleteAllData(),
        expect: () => <CompanyProfileState>[],
        verify: (_) => expect(localData.erasures, 0),
      );

      for (final (description, fails) in [('the deletion ends', false), ('the deletion fails', true)]) {
        test('emits nothing more when the cubit closes before $description', () async {
          localData.gate = Completer<void>();
          if (fails) localData.failure = Exception('disk I/O error');
          final cubit = build();

          final deletion = cubit.deleteAllData();
          await cubit.close();
          localData.gate!.complete();
          await deletion;

          expect(cubit.state.deletion, DataDeletion.deleting);
        });
      }
    });
  });
}
