import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

void main() {
  final profile = CompanyProfile(name: '반짝 클린');
  final failure = Exception('storage failed');

  late MockCompanyProfileRepository companyProfile;

  CompanyProfileCubit build() => CompanyProfileCubit(companyProfile: companyProfile);

  CompanyProfileState ready({String name = '', NameEntry entry = NameEntry.editing}) =>
      CompanyProfileState(status: CompanyProfileStatus.ready, name: name, entry: entry);

  setUpAll(() => registerFallbackValue(profile));

  setUp(() {
    companyProfile = MockCompanyProfileRepository();
    when(() => companyProfile.save(any())).thenAnswer((_) async {});
  });

  group('CompanyProfileState', () {
    test('is equal to a state with the same fields', () {
      expect(ready(name: '반짝 클린'), ready(name: '반짝 클린'));
      expect(ready(name: '반짝 클린').hashCode, ready(name: '반짝 클린').hashCode);
    });

    test('differs from a state with another field value', () {
      expect(ready(), isNot(const CompanyProfileState()));
      expect(ready(), isNot(ready(name: '반짝 클린')));
      expect(ready(), isNot(ready(entry: NameEntry.saved)));
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
  });
}
