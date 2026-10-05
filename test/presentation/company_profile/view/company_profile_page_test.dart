import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:kkomkkomi/presentation/shared/notice.dart';
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
        openCaptures: FakeOpenCaptureRepository(),
        localData: FakeLocalDataRepository(),
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
      expect(field(tester).decoration!.errorMessage, isNull);
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

      expect(field(tester).decoration!.errorMessage, 'Enter a name.');
      expect(find.byType(SnackBar), findsNothing);
      expect(companyProfile.profile, CompanyProfile(name: '반짝 클린'));
    });

    testWidgets('shows a failure of storage under the name field', (tester) async {
      await pumpPage(tester);
      companyProfile.failure = failure;

      await tester.enterText(find.byType(TextField), '반짝 클린');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(field(tester).decoration!.errorMessage, "Can't save right now. Try again.");
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
          openCaptures: FakeOpenCaptureRepository(),
          localData: FakeLocalDataRepository(),
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
      expect(field(tester).decoration!.errorMessage, "Can't save right now. Try again.");
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
      expect(field(tester).decoration!.errorMessage, '이름을 입력해 주세요.');

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

  group('the plan', () {
    late FakeEntitlements entitlements;

    Future<void> pumpWithPlan(WidgetTester tester, {Plan plan = Plan.free, Locale? locale}) async {
      entitlements = FakeEntitlements(plan: plan);
      await tester.pumpApp(
        const CompanyProfilePage(),
        locale: locale,
        entitlements: entitlements,
        repositories: Repositories(
          clients: FakeClientRepository(),
          visits: FakeVisitRepository(),
          companyProfile: FakeCompanyProfileRepository(),
          publishing: MockPublishRepository(),
          openCaptures: FakeOpenCaptureRepository(),
          localData: FakeLocalDataRepository(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the plan that the store gave, and each plan that it reports', (tester) async {
      await pumpWithPlan(tester, plan: Plan.basic);

      expect(find.text('Plan'), findsOneWidget);
      expect(find.text("You're on the Basic plan."), findsOneWidget);

      entitlements.change(Plan.pro);
      await tester.pumpAndSettle();

      expect(find.text("You're on the Pro plan."), findsOneWidget);
    });

    testWidgets('shows the plan that the store reported while the read was on its way', (tester) async {
      final gate = Completer<void>();
      entitlements = FakeEntitlements()..planGate = gate;
      await tester.pumpApp(
        const CompanyProfilePage(),
        entitlements: entitlements,
        repositories: Repositories(
          clients: FakeClientRepository(),
          visits: FakeVisitRepository(),
          companyProfile: FakeCompanyProfileRepository(),
          publishing: MockPublishRepository(),
          openCaptures: FakeOpenCaptureRepository(),
          localData: FakeLocalDataRepository(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("You're on"), findsNothing);

      entitlements.change(Plan.pro);
      await tester.pumpAndSettle();
      entitlements.plan = Plan.free;
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text("You're on the Pro plan."), findsOneWidget);
    });

    testWidgets('opens the plans screen', (tester) async {
      await pumpWithPlan(tester);

      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'See Plans'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'See Plans'));
      await tester.pumpAndSettle();

      expect(find.byType(PlansPage), findsOneWidget);
    });

    testWidgets('speaks Korean', (tester) async {
      await pumpWithPlan(tester, locale: const Locale('ko'));

      expect(find.text('요금제'), findsOneWidget);
      expect(find.text('지금은 무료 요금제를 쓰고 있어요.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '요금제 보기'), findsOneWidget);
    });

    for (final locale in [const Locale('en'), const Locale('ko')]) {
      testWidgets('cuts none of its texts on a narrow screen at the largest text size in ${locale.languageCode}', (
        tester,
      ) async {
        tester.useNarrowScreenWithLargestText();
        await pumpWithPlan(tester, plan: Plan.basic, locale: locale);

        final english = locale.languageCode == 'en';
        final button = english ? 'See Plans' : '요금제 보기';
        await tester.ensureVisible(find.widgetWithText(OutlinedButton, button));
        await tester.pumpAndSettle();
        tester
          ..expectWholeText(english ? "You're on the Basic plan." : '지금은 베이직 요금제를 쓰고 있어요.')
          ..expectWholeText(button);
      });
    }
  });

  group('the deletion of all data', () {
    late FakeLocalDataRepository localData;
    late FakePhotoStore photoStore;
    late FakePublishRepository publishing;
    late FakePublisher publisher;
    late FakeIdentity identity;

    /// Opens the screen over a host screen, as the client list opens it, with a backend when [backend] is true.
    Future<void> pumpOverHost(WidgetTester tester, {bool backend = false, Locale? locale}) async {
      localData = FakeLocalDataRepository();
      photoStore = FakePhotoStore();
      publishing = FakePublishRepository();
      publisher = FakePublisher()..isAvailable = backend;
      identity = FakeIdentity(userId: 'owner-1');
      final repositories = Repositories(
        clients: FakeClientRepository(),
        visits: FakeVisitRepository(),
        companyProfile: FakeCompanyProfileRepository(profile: CompanyProfile(name: '반짝 클린')),
        publishing: publishing,
        openCaptures: FakeOpenCaptureRepository(),
        localData: localData,
      );
      await tester.pumpApp(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(CompanyProfilePage.route()),
              child: const Text('host'),
            ),
          ),
        ),
        locale: locale,
        repositories: repositories,
        identity: identity,
        photoStore: photoStore,
        publishQueue: publishQueueOf(repositories, publisher: publisher, identity: identity, photoStore: photoStore),
      );
      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();
    }

    Future<void> tapDelete(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, label));
      await tester.pumpAndSettle();
    }

    testWidgets('says what it deletes, asks first, then deletes and goes back to the screen below', (tester) async {
      await pumpOverHost(tester);
      expect(find.text('Delete all data'), findsOneWidget);
      expect(
        find.text(
          'Deletes the clients, visits, photos, and company profile on this phone, the reports and photos you shared '
          'as links, and your anonymous account.',
        ),
        findsOneWidget,
      );

      await tapDelete(tester, 'Delete All Data');
      expect(find.text('Delete all data?'), findsOneWidget);
      expect(
        find.text(
          'This deletes the clients, zones, visits, photos, and company profile on this phone, the reports and photos '
          "you uploaded, and your anonymous account. You can't get them back, and the links you shared stop opening.",
        ),
        findsOneWidget,
      );
      expect(localData.erasures, 0);
      expect(tester.filledButtonColor('Delete'), appTheme().colorScheme.error);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(localData.erasures, 1);
      expect(photoStore.deletionsOfAll, 1);
      expect(find.byType(CompanyProfilePage), findsNothing);
      expect(find.text('host'), findsOneWidget);
      expect(find.widgetWithText(SnackBar, 'All data deleted.'), findsOneWidget);
    });

    testWidgets('deletes nothing when the person closes the question', (tester) async {
      await pumpOverHost(tester);

      await tapDelete(tester, 'Delete All Data');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(localData.erasures, 0);
      expect(find.byType(CompanyProfilePage), findsOneWidget);
    });

    testWidgets('deletes the published data and the account before the data on the phone', (tester) async {
      await pumpOverHost(tester, backend: true);
      publishing.pagesById['page-1'] = ClientPage(
        id: 'page-1',
        clientId: 'client-1',
        createdAt: DateTime.utc(2026, 10),
      );
      localData.onErase = () {
        expect(publisher.calls, ['deletePage page-1']);
        expect(identity.deletions, 1);
      };

      await tapDelete(tester, 'Delete All Data');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(localData.erasures, 1);
      expect(find.byType(CompanyProfilePage), findsNothing);
    });

    testWidgets('stays open and says which step failed, and the next try goes on', (tester) async {
      await pumpOverHost(tester, backend: true);
      identity.deleteFailures.add(Exception('network-request-failed'));

      await tapDelete(tester, 'Delete All Data');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(CompanyProfilePage), findsOneWidget);
      const message =
          "Can't delete your anonymous account. Check your connection and try again. Your uploaded reports and photos "
          'are deleted, and the data on this phone is still here.';
      expect(find.text(message), findsOneWidget);
      expect(tester.noticeToneOf(message), NoticeTone.error);
      expect(localData.erasures, 0);

      await tapDelete(tester, 'Delete All Data');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(localData.erasures, 1);
      expect(find.byType(CompanyProfilePage), findsNothing);
    });

    testWidgets('shows its progress, takes no second press, and stays open while it runs', (tester) async {
      await pumpOverHost(tester);
      localData.gate = Completer<void>();

      await tapDelete(tester, 'Delete All Data');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text("Deleting your data. Keep this screen open until it's done."), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Delete All Data')).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(CompanyProfilePage), findsOneWidget);

      localData.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CompanyProfilePage), findsNothing);
    });

    testWidgets('speaks Korean', (tester) async {
      await pumpOverHost(tester, locale: const Locale('ko'));
      expect(find.text('모든 데이터 지우기'), findsNWidgets(2));
      expect(find.text('이 휴대폰의 거래처, 방문 기록, 사진, 회사 정보와, 링크로 올린 보고서와 사진, 익명 계정을 모두 지워요.'), findsOneWidget);

      await tapDelete(tester, '모든 데이터 지우기');
      expect(find.text('모든 데이터를 지울까요?'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '닫기'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '지우기'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SnackBar, '모든 데이터를 지웠어요.'), findsOneWidget);
    });
  });

  group('CompanyProfileView', () {
    late CompanyProfileCubit cubit;

    setUp(() => cubit = _MockCompanyProfileCubit());

    testWidgets('shows a progress indicator while the profile loads', (tester) async {
      when(() => cubit.state).thenReturn(const CompanyProfileState());

      await tester.pumpApp(
        RepositoryProvider<Entitlements>.value(
          value: FakeEntitlements(),
          child: BlocProvider.value(value: cubit, child: const CompanyProfileView()),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('takes no name from the button or the keyboard while a name is on its way to storage', (tester) async {
      when(() => cubit.state).thenReturn(
        const CompanyProfileState(status: CompanyProfileStatus.ready, name: '반짝 클린', entry: NameEntry.saving),
      );
      await tester.pumpApp(
        RepositoryProvider<Entitlements>.value(
          value: FakeEntitlements(),
          child: BlocProvider.value(value: cubit, child: const CompanyProfileView()),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save'), warnIfMissed: false);
      await tester.enterText(find.byType(TextField), '다른 이름');
      await tester.testTextInput.receiveAction(TextInputAction.done);

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      verifyNever(() => cubit.save(any()));
      // The field keeps the name that is on its way, so the message about the saved name is about this name.
      expect(field(tester).controller!.text, '반짝 클린');
    });

    testWidgets('takes no name from the keyboard while a deletion of all data is on its way', (tester) async {
      when(() => cubit.state).thenReturn(
        const CompanyProfileState(
          status: CompanyProfileStatus.ready,
          name: '반짝 클린',
        ).withDeletion(DataDeletion.deleting),
      );
      await tester.pumpApp(
        RepositoryProvider<Entitlements>.value(
          value: FakeEntitlements(),
          child: BlocProvider.value(value: cubit, child: const CompanyProfileView()),
        ),
      );

      // The screen takes no touch, and the keyboard that was open before the deletion can still submit.
      tester.testTextInput.register();
      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      verifyNever(() => cubit.save(any()));
    });

    testWidgets('keeps what the person typed when the saved name changes', (tester) async {
      final states = StreamController<CompanyProfileState>();
      addTearDown(states.close);
      const ready = CompanyProfileState(status: CompanyProfileStatus.ready, name: '반짝 클린');
      whenListen(cubit, states.stream, initialState: ready);
      await tester.pumpApp(
        RepositoryProvider<Entitlements>.value(
          value: FakeEntitlements(),
          child: BlocProvider.value(value: cubit, child: const CompanyProfileView()),
        ),
      );

      await tester.enterText(find.byType(TextField), '반짝 클린 2호');
      states.add(ready.copyWith(name: '반짝 클린 2', entry: NameEntry.saved));
      await tester.pump();

      expect(field(tester).controller!.text, '반짝 클린 2호');
    });

    const ready = CompanyProfileState(status: CompanyProfileStatus.ready, name: '반짝 클린');
    final failures = {
      DeletionStep.publishedData: (
        "Can't delete the reports and photos you uploaded. Check your connection and try again. The data on this "
            'phone is still here.',
        '올린 보고서와 사진을 지우지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요. 휴대폰의 데이터는 그대로 있어요.',
      ),
      DeletionStep.account: (
        "Can't delete your anonymous account. Check your connection and try again. Your uploaded reports and photos "
            'are deleted, and the data on this phone is still here.',
        '익명 계정을 지우지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요. 올린 보고서와 사진은 지웠고, 휴대폰의 데이터는 그대로 있어요.',
      ),
      DeletionStep.deviceData: (
        "Can't delete the data on this phone. Try again. The data on the server and your anonymous account are "
            'deleted.',
        '휴대폰의 데이터를 지우지 못했어요. 다시 시도해 주세요. 서버의 데이터와 익명 계정은 지웠어요.',
      ),
    };

    for (final MapEntry(key: step, value: (english, _)) in failures.entries) {
      testWidgets('names the step ${step.name} when the deletion stopped there', (tester) async {
        when(() => cubit.state).thenReturn(ready.withDeletion(DataDeletion.idle, failure: step));
        await tester.pumpApp(
          RepositoryProvider<Entitlements>.value(
            value: FakeEntitlements(),
            child: BlocProvider.value(value: cubit, child: const CompanyProfileView()),
          ),
        );

        expect(find.text(english), findsOneWidget);
        for (final other in failures.values.where((texts) => texts.$1 != english)) {
          expect(find.text(other.$1), findsNothing);
        }
        expect(
          tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Delete All Data')).onPressed,
          isNotNull,
        );
      });
    }

    group('on a screen 320 pixels wide at the largest text size', () {
      for (final locale in [const Locale('en'), const Locale('ko')]) {
        testWidgets('cuts none of the texts of the deletion in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();
          final english = locale.languageCode == 'en';
          final states = StreamController<CompanyProfileState>();
          addTearDown(states.close);
          whenListen(cubit, states.stream, initialState: ready);
          await tester.pumpApp(
            RepositoryProvider<Entitlements>.value(
              value: FakeEntitlements(),
              child: BlocProvider.value(value: cubit, child: const CompanyProfileView()),
            ),
            locale: locale,
          );

          // The plan arrives after the first frame and moves the controls under it.
          await tester.pumpAndSettle();
          final button = english ? 'Delete All Data' : '모든 데이터 지우기';
          await tester.ensureVisible(find.widgetWithText(OutlinedButton, button));
          await tester.pumpAndSettle();
          tester
            ..expectWholeText(english ? 'Delete all data' : '모든 데이터 지우기')
            ..expectWholeText(
              english
                  ? 'Deletes the clients, visits, photos, and company profile on this phone, the reports and photos '
                        'you shared as links, and your anonymous account.'
                  : '이 휴대폰의 거래처, 방문 기록, 사진, 회사 정보와, 링크로 올린 보고서와 사진, 익명 계정을 모두 지워요.',
            );

          await tester.tap(find.widgetWithText(OutlinedButton, button));
          await tester.pumpAndSettle();
          tester
            ..expectWholeText(english ? 'Delete all data?' : '모든 데이터를 지울까요?')
            ..expectWholeText(english ? 'Delete' : '지우기');
          await tester.tap(find.widgetWithText(TextButton, english ? 'Cancel' : '닫기'));
          await tester.pumpAndSettle();

          // The state arrives through a stream, which takes one frame to deliver and one to build.
          states.add(ready.withDeletion(DataDeletion.deleting));
          await tester.pump();
          await tester.pump();
          // The progress bar never settles, so the scroll gets a fixed time.
          await tester.ensureVisible(find.byType(LinearProgressIndicator));
          await tester.pump(const Duration(seconds: 1));
          tester.expectWholeText(
            english
                ? "Deleting your data. Keep this screen open until it's done."
                : '데이터를 지우고 있어요. 다 지울 때까지 이 화면을 열어 두세요.',
          );

          for (final MapEntry(key: step, value: texts) in failures.entries) {
            states.add(ready.withDeletion(DataDeletion.idle, failure: step));
            await tester.pump();
            await tester.pump();
            final text = english ? texts.$1 : texts.$2;
            await tester.ensureVisible(find.text(text));
            await tester.pumpAndSettle();
            tester.expectWholeText(text);
          }
        });
      }
    });
  });
}
