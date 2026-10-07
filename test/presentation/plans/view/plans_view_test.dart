// 📦 Package imports:
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:kkomkkomi/presentation/shared/notice.dart';

import '../../../helpers/helpers.dart';

class _MockPlansCubit extends MockCubit<PlansState> implements PlansCubit;

const _basicMonthly = PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.monthly, price: 'p1');
const _basicAnnual = PlanOffer(id: 'basic_annual', plan: Plan.basic, period: BillingPeriod.annual, price: 'p2');
const _proMonthly = PlanOffer(id: 'pro_monthly', plan: Plan.pro, period: BillingPeriod.monthly, price: 'p3');
const _proAnnual = PlanOffer(id: 'pro_annual', plan: Plan.pro, period: BillingPeriod.annual, price: 'p4');

const _loaded = PlansState(
  sellsPlans: true,
  status: PlansStatus.ready,
  offersStatus: OffersStatus.loaded,
  offers: [_basicMonthly, _basicAnnual, _proMonthly, _proAnnual],
);

void main() {
  late PlansCubit cubit;

  setUpAll(() => registerFallbackValue(_basicMonthly));

  setUp(() {
    cubit = _MockPlansCubit();
    when(() => cubit.purchase(any())).thenAnswer((_) async {});
    when(() => cubit.restore()).thenAnswer((_) async {});
    when(() => cubit.retry()).thenAnswer((_) async {});
    when(() => cubit.openManagement()).thenAnswer((_) async {});
    when(() => cubit.open(any())).thenAnswer((_) async {});
    when(() => cubit.refresh()).thenAnswer((_) async {});
  });

  setUpAll(() => registerFallbackValue(Uri()));

  Future<void> pumpView(WidgetTester tester, PlansState state, {Locale? locale}) async {
    when(() => cubit.state).thenReturn(state);
    await tester.pumpApp(
      BlocProvider.value(value: cubit, child: const PlansView()),
      locale: locale,
    );
  }

  Finder button(String text) =>
      find.ancestor(of: find.text(text), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

  group('PlansView', () {
    testWidgets('shows a progress indicator while the plan loads', (tester) async {
      await pumpView(tester, const PlansState(sellsPlans: true));

      expect(find.widgetWithText(AppBar, 'Plans'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Current plan'), findsNothing);
    });

    testWidgets('shows the current plan and what it holds', (tester) async {
      await pumpView(tester, _loaded);

      expect(find.text('Current plan'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Keep up to 2 clients.'), findsOneWidget);
      expect(find.text('Reports show “Report made with Kkomkkomi” at the bottom.'), findsOneWidget);
    });

    testWidgets('shows each paid plan with what it holds and one control for each period with the store price', (
      tester,
    ) async {
      await pumpView(tester, _loaded);

      expect(find.text('Basic'), findsOneWidget);
      expect(find.text('Keep up to 5 clients.'), findsOneWidget);
      expect(find.text('Pro'), findsOneWidget);
      expect(find.text('Keep as many clients as you need.'), findsOneWidget);
      expect(find.text("Reports don't show “Report made with Kkomkkomi”."), findsNWidgets(2));
      for (final label in [
        'Subscribe Monthly (p1 per month)',
        'Subscribe Yearly (p2 per year)',
        'Subscribe Monthly (p3 per month)',
        'Subscribe Yearly (p4 per year)',
      ]) {
        expect(find.widgetWithText(FilledButton, label), findsOneWidget);
      }
      expect(find.text("Archived clients don't count."), findsOneWidget);
      expect(
        find.text(
          'A subscription renews automatically at the end of each period until you cancel it, and the store charges '
          'your store account. You can cancel it in the subscription settings of the store.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('buys the offer of the pressed control', (tester) async {
      await pumpView(tester, _loaded);

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Subscribe Yearly (p4 per year)'));
      await tester.tap(find.widgetWithText(FilledButton, 'Subscribe Yearly (p4 per year)'));

      verify(() => cubit.purchase(_proAnnual)).called(1);
    });

    testWidgets('shows only the plans that the store sells', (tester) async {
      await pumpView(
        tester,
        const PlansState(
          sellsPlans: true,
          status: PlansStatus.ready,
          offersStatus: OffersStatus.loaded,
          offers: [_proMonthly],
        ),
      );

      expect(find.text('Basic'), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    // Review Focus 6.
    testWidgets('shows the product in use as a control that buys nothing', (tester) async {
      await pumpView(
        tester,
        PlansState(
          sellsPlans: true,
          status: PlansStatus.ready,
          plan: Plan.basic,
          offersStatus: OffersStatus.loaded,
          offers: [
            _basicMonthly,
            PlanOffer(id: _basicAnnual.id, plan: Plan.basic, period: BillingPeriod.annual, price: 'p2', isActive: true),
            _proMonthly,
          ],
        ),
      );

      expect(find.widgetWithText(FilledButton, 'Subscribe Monthly (p1 per month)'), findsOneWidget);
      final inUse = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'In use: yearly (p2 per year)'));
      expect(inUse.onPressed, isNull);
    });

    testWidgets('shows both periods of the current plan in use when the store named no product of it', (tester) async {
      await pumpView(
        tester,
        const PlansState(
          sellsPlans: true,
          status: PlansStatus.ready,
          plan: Plan.pro,
          offersStatus: OffersStatus.loaded,
          offers: [_proMonthly, _proAnnual],
        ),
      );

      expect(find.widgetWithText(OutlinedButton, 'In use: monthly (p3 per month)'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'In use: yearly (p4 per year)'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Pro'), findsNWidgets(2));
    });

    testWidgets('shows a progress indicator while the offers load', (tester) async {
      await pumpView(tester, const PlansState(sellsPlans: true, status: PlansStatus.ready));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    // Review Focus 1.
    testWidgets('shows the plan, a retry, restore, and the links, and no purchase control, when offers did not load', (
      tester,
    ) async {
      await pumpView(
        tester,
        const PlansState(sellsPlans: true, status: PlansStatus.ready, offersStatus: OffersStatus.failed),
      );

      expect(find.text('Free'), findsOneWidget);
      expect(find.text("Can't load the subscriptions. Check your connection and try again."), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Restore Purchases'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Terms of Use'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Privacy Policy'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Try Again'));
      verify(() => cubit.retry()).called(1);
    });

    testWidgets('says that the build cannot sell, with no offer, no restore, and no purchase control', (tester) async {
      await pumpView(tester, const PlansState(sellsPlans: false, status: PlansStatus.ready));

      expect(find.text("Subscriptions aren't available in this version of the app."), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.widgetWithText(TextButton, 'Terms of Use'), findsOneWidget);
    });

    testWidgets('restores from its control', (tester) async {
      await pumpView(tester, _loaded);

      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Restore Purchases'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Restore Purchases'));

      verify(() => cubit.restore()).called(1);
    });

    testWidgets('shows no subscription management when the store knows no page', (tester) async {
      await pumpView(tester, _loaded);

      expect(find.text('Manage Subscription'), findsNothing);
    });

    testWidgets('opens the subscription management when the store knows its page', (tester) async {
      await pumpView(
        tester,
        _loaded.copyWith(managementUrl: () => Uri.parse('https://apps.apple.com/account/subscriptions')),
      );

      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Manage Subscription'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Manage Subscription'));

      verify(() => cubit.openManagement()).called(1);
    });

    for (final (locale, privacy) in [
      (const Locale('en'), 'https://kkomkkomi.web.app/privacy/en/'),
      (const Locale('ko'), 'https://kkomkkomi.web.app/privacy/'),
    ]) {
      testWidgets('opens the terms of use of Apple and the privacy policy in ${locale.languageCode}', (tester) async {
        await pumpView(tester, _loaded, locale: locale);
        final english = locale.languageCode == 'en';

        await tester.ensureVisible(button(english ? 'Terms of Use' : '이용약관'));
        await tester.tap(button(english ? 'Terms of Use' : '이용약관'));
        await tester.tap(button(english ? 'Privacy Policy' : '개인정보 처리방침'));

        verify(() => cubit.open(Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/')))
            .called(1);
        verify(() => cubit.open(Uri.parse(privacy))).called(1);
      });
    }

    for (final (notice, tone, text) in [
      (
        PlansNotice.purchasePending,
        NoticeTone.info,
        "The purchase is waiting for approval. Your plan changes once it's approved.",
      ),
      (PlansNotice.purchaseFailed, NoticeTone.error, "Can't complete the purchase. Try again later."),
      (PlansNotice.restored, NoticeTone.info, 'Your purchases are restored.'),
      (PlansNotice.nothingFound, NoticeTone.info, 'No purchases to restore.'),
      (
        PlansNotice.restoreFailed,
        NoticeTone.error,
        "Can't restore your purchases. Check your connection and try again.",
      ),
      (PlansNotice.linkFailed, NoticeTone.error, "Can't open the page."),
    ]) {
      testWidgets('shows the notice of $notice', (tester) async {
        await pumpView(tester, _loaded.withAction(isBusy: false, notice: notice));

        expect(find.text(text), findsOneWidget);
        expect(tester.widget<Notice>(find.ancestor(of: find.text(text), matching: find.byType(Notice))).tone, tone);
      });
    }

    // Review Focus 5.
    testWidgets('takes no touch and stays open while an action is on its way', (tester) async {
      await pumpView(tester, _loaded.withAction(isBusy: true));

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Subscribe Monthly (p1 per month)'), warnIfMissed: false);
      verifyNever(() => cubit.purchase(any()));
      final popScope = find.byWidgetPredicate((widget) => widget is PopScope);
      expect(tester.widget<PopScope>(popScope).canPop, isFalse);
    });

    testWidgets('reads the plan and the offers again each time that the app comes back to the foreground', (
      tester,
    ) async {
      await pumpView(tester, _loaded);

      // The store page of the subscription management opens over the app, and the person comes back from it.
      [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      verifyNever(() => cubit.refresh());

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      verify(() => cubit.refresh()).called(1);

      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      verify(() => cubit.refresh()).called(1);
    });

    testWidgets('stops following the app when the screen closes', (tester) async {
      await pumpView(tester, _loaded);
      await tester.pumpWidget(const SizedBox());

      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      verifyNever(() => cubit.refresh());
    });

    testWidgets('speaks Korean', (tester) async {
      await pumpView(
        tester,
        PlansState(
          sellsPlans: true,
          status: PlansStatus.ready,
          plan: Plan.basic,
          offersStatus: OffersStatus.loaded,
          offers: [
            PlanOffer(
              id: _basicMonthly.id,
              plan: Plan.basic,
              period: BillingPeriod.monthly,
              price: 'p1',
              isActive: true,
            ),
            _basicAnnual,
            _proMonthly,
            _proAnnual,
          ],
          managementUrl: Uri.parse('https://play.google.com/store/account/subscriptions'),
          notice: PlansNotice.nothingFound,
        ),
        locale: const Locale('ko'),
      );

      expect(find.widgetWithText(AppBar, '요금제'), findsOneWidget);
      expect(find.text('지금 쓰는 요금제'), findsOneWidget);
      expect(find.text('베이직'), findsNWidgets(2));
      expect(find.text('프로'), findsOneWidget);
      expect(find.text('거래처를 5곳까지 둘 수 있어요.'), findsNWidgets(2));
      expect(find.text('거래처를 개수 제한 없이 둘 수 있어요.'), findsOneWidget);
      expect(find.text('보고서에 ‘꼼꼬미로 작성됨’ 문구가 들어가지 않아요.'), findsNWidgets(3));
      expect(find.text('이용 중: 월간 (매달 p1)'), findsOneWidget);
      expect(find.text('연간 구독하기 (매년 p2)'), findsOneWidget);
      expect(find.text('월간 구독하기 (매달 p3)'), findsOneWidget);
      expect(find.text('복원할 구매 내역이 없어요.'), findsOneWidget);
      expect(find.text('보관한 거래처는 개수에 들어가지 않아요.'), findsOneWidget);
      expect(find.text('구매 복원하기'), findsOneWidget);
      expect(find.text('구독 관리하기'), findsOneWidget);
      expect(find.text('이용약관'), findsOneWidget);
      expect(find.text('개인정보 처리방침'), findsOneWidget);
    });

    testWidgets('names the Free plan and its footer in Korean', (tester) async {
      await pumpView(
        tester,
        const PlansState(sellsPlans: false, status: PlansStatus.ready),
        locale: const Locale('ko'),
      );

      expect(find.text('무료'), findsOneWidget);
      expect(find.text('거래처를 2곳까지 둘 수 있어요.'), findsOneWidget);
      expect(find.text('보고서 아래에 ‘꼼꼬미로 작성됨’ 문구가 들어가요.'), findsOneWidget);
      expect(find.text('이 버전의 앱에서는 요금제를 구독할 수 없어요.'), findsOneWidget);
    });
  });
}
