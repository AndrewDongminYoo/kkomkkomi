import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

class _MockCompanyProfileCubit extends MockCubit<CompanyProfileState> implements CompanyProfileCubit;

void main() {
  final failure = Exception('storage failed');

  late FakeCompanyProfileRepository companyProfile;

  Future<void> pumpPage(WidgetTester tester, {CompanyProfile? saved, Locale? locale, Exception? loadFailure}) async {
    companyProfile = FakeCompanyProfileRepository(profile: saved)..failure = loadFailure;
    await tester.pumpApp(
      const CompanyProfilePage(),
      locale: locale,
      repositories: Repositories(
        clients: FakeClientRepository(),
        visits: FakeVisitRepository(),
        companyProfile: companyProfile,
        publishing: MockPublishRepository(),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextField field(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField));

  group('CompanyProfilePage', () {
    testWidgets('renders CompanyProfileView with an empty name field when no profile was saved', (tester) async {
      await pumpPage(tester);

      expect(find.byType(CompanyProfileView), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Company profile'), findsOneWidget);
      expect(find.text('Company name'), findsOneWidget);
      expect(find.text('Reports show this name at the top.'), findsOneWidget);
      expect(field(tester).controller!.text, isEmpty);
    });

    testWidgets('opens with the saved company name in the field', (tester) async {
      await pumpPage(tester, saved: CompanyProfile(name: '반짝 클린'));

      expect(field(tester).controller!.text, '반짝 클린');
    });

    testWidgets('saves the name from the button and says so', (tester) async {
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), ' 반짝 클린 ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(companyProfile.profile, CompanyProfile(name: '반짝 클린'));
      expect(find.widgetWithText(SnackBar, 'Company name saved.'), findsOneWidget);
      expect(field(tester).decoration!.errorText, isNull);
      expect(field(tester).controller!.text, ' 반짝 클린 ');
    });

    testWidgets('saves the name from the keyboard, and says so again after each save', (tester) async {
      await pumpPage(tester, saved: CompanyProfile(name: '반짝 클린'));

      await tester.enterText(find.byType(TextField), '반짝 클린 2호점');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      // The message leaves after its time on the screen, which starts when it has come in.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      // The keyboard action closed the keyboard, so the second save comes from the button.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(companyProfile.profile, CompanyProfile(name: '반짝 클린 2호점'));
      expect(find.widgetWithText(SnackBar, 'Company name saved.'), findsOneWidget);
    });

    testWidgets('shows the validation message under the name field and keeps the saved name', (tester) async {
      await pumpPage(tester, saved: CompanyProfile(name: '반짝 클린'));

      await tester.enterText(find.byType(TextField), '  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(field(tester).decoration!.errorText, 'Enter a name.');
      expect(find.byType(SnackBar), findsNothing);
      expect(companyProfile.profile, CompanyProfile(name: '반짝 클린'));
    });

    testWidgets('shows a failure of storage under the name field', (tester) async {
      await pumpPage(tester);
      companyProfile.failure = failure;

      await tester.enterText(find.byType(TextField), '반짝 클린');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(field(tester).decoration!.errorText, "Can't save right now. Try again.");
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('stays open while a name is on its way to storage, so that a failure reaches the person', (
      tester,
    ) async {
      companyProfile = FakeCompanyProfileRepository();
      await tester.pumpApp(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(CompanyProfilePage.route()),
              child: const Text('host'),
            ),
          ),
        ),
        repositories: Repositories(
          clients: FakeClientRepository(),
          visits: FakeVisitRepository(),
          companyProfile: companyProfile,
          publishing: MockPublishRepository(),
        ),
      );
      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();
      companyProfile.gate = Completer<void>();

      await tester.enterText(find.byType(TextField), '반짝 클린');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.tap(find.byType(BackButton), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(CompanyProfilePage), findsOneWidget);

      companyProfile.gate!.completeError(failure);
      companyProfile.gate = null;
      await tester.pumpAndSettle();
      expect(field(tester).decoration!.errorText, "Can't save right now. Try again.");
      expect(field(tester).controller!.text, '반짝 클린');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CompanyProfilePage), findsNothing);
    });

    testWidgets('shows a message and a retry control when the profile does not load, and loads it on retry', (
      tester,
    ) async {
      await pumpPage(
        tester,
        saved: CompanyProfile(name: '반짝 클린'),
        loadFailure: failure,
      );

      expect(find.text("Can't load your company profile. Try again."), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      companyProfile.failure = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Try Again'));
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, '반짝 클린');
    });

    testWidgets('shows the screen in Korean', (tester) async {
      await pumpPage(tester, locale: const Locale('ko'));

      expect(find.widgetWithText(AppBar, '회사 정보'), findsOneWidget);
      expect(find.text('회사 이름'), findsOneWidget);
      expect(find.text('보고서 맨 위에 들어갈 이름이에요.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
      await tester.pump();
      expect(field(tester).decoration!.errorText, '이름을 입력해 주세요.');

      await tester.enterText(find.byType(TextField), '반짝 클린');
      await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
      await tester.pump();
      expect(find.widgetWithText(SnackBar, '회사 이름을 저장했어요.'), findsOneWidget);
    });

    testWidgets('shows the load failure in Korean', (tester) async {
      await pumpPage(tester, locale: const Locale('ko'), loadFailure: failure);

      expect(find.text('회사 정보를 불러오지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '다시 불러오기'), findsOneWidget);
    });

    group('on a screen 320 pixels wide at the largest text size', () {
      for (final (locale, label, helper, save, emptyProblem, failedProblem, saved) in [
        (
          const Locale('en'),
          'Company name',
          'Reports show this name at the top.',
          'Save',
          'Enter a name.',
          "Can't save right now. Try again.",
          'Company name saved.',
        ),
        (
          const Locale('ko'),
          '회사 이름',
          '보고서 맨 위에 들어갈 이름이에요.',
          '저장하기',
          '이름을 입력해 주세요.',
          '저장하지 못했어요. 다시 시도해 주세요.',
          '회사 이름을 저장했어요.',
        ),
      ]) {
        testWidgets('fits the form and cuts none of its text in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, locale: locale);
          tester
            ..expectWholeText(label)
            ..expectWholeText(helper)
            ..expectWholeText(save);

          // The form is taller than the screen at this text size, so the button is brought into view first.
          Future<void> tapSave() async {
            await tester.ensureVisible(find.widgetWithText(FilledButton, save));
            await tester.pumpAndSettle();
            await tester.tap(find.widgetWithText(FilledButton, save));
            await tester.pumpAndSettle();
          }

          await tapSave();
          tester.expectWholeText(emptyProblem);

          companyProfile.failure = failure;
          await tester.enterText(find.byType(TextField), '반짝 클린');
          await tapSave();
          tester.expectWholeText(failedProblem);

          companyProfile.failure = null;
          await tapSave();
          expect(find.byType(SnackBar), findsOneWidget);
          tester.expectWholeText(saved);
        });
      }

      for (final (locale, message, retry) in [
        (const Locale('en'), "Can't load your company profile. Try again.", 'Try Again'),
        (const Locale('ko'), '회사 정보를 불러오지 못했어요. 다시 시도해 주세요.', '다시 불러오기'),
      ]) {
        testWidgets('fits the message of a failed load in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(tester, locale: locale, loadFailure: failure);

          tester
            ..expectWholeText(message)
            ..expectWholeText(retry);
        });
      }
    });
  });

  group('CompanyProfileView', () {
    late CompanyProfileCubit cubit;

    setUp(() => cubit = _MockCompanyProfileCubit());

    testWidgets('shows a progress indicator while the profile loads', (tester) async {
      when(() => cubit.state).thenReturn(const CompanyProfileState());

      await tester.pumpApp(BlocProvider.value(value: cubit, child: const CompanyProfileView()));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('takes no name from the button or the keyboard while a name is on its way to storage', (tester) async {
      when(() => cubit.state).thenReturn(
        const CompanyProfileState(status: CompanyProfileStatus.ready, name: '반짝 클린', entry: NameEntry.saving),
      );
      await tester.pumpApp(BlocProvider.value(value: cubit, child: const CompanyProfileView()));

      await tester.tap(find.widgetWithText(FilledButton, 'Save'), warnIfMissed: false);
      await tester.enterText(find.byType(TextField), '다른 이름');
      await tester.testTextInput.receiveAction(TextInputAction.done);

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      verifyNever(() => cubit.save(any()));
      // The field keeps the name that is on its way, so the message about the saved name is about this name.
      expect(field(tester).controller!.text, '반짝 클린');
    });

    testWidgets('keeps what the person typed when the saved name changes', (tester) async {
      final states = StreamController<CompanyProfileState>();
      addTearDown(states.close);
      const ready = CompanyProfileState(status: CompanyProfileStatus.ready, name: '반짝 클린');
      whenListen(cubit, states.stream, initialState: ready);
      await tester.pumpApp(BlocProvider.value(value: cubit, child: const CompanyProfileView()));

      await tester.enterText(find.byType(TextField), '반짝 클린 2호');
      states.add(ready.copyWith(name: '반짝 클린 2', entry: NameEntry.saved));
      await tester.pump();

      expect(field(tester).controller!.text, '반짝 클린 2호');
    });
  });
}
