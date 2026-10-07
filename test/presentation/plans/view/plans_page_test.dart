// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

import '../../../helpers/helpers.dart';

const _offers = [
  PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.monthly, price: 'p1'),
  PlanOffer(id: 'basic_annual', plan: Plan.basic, period: BillingPeriod.annual, price: 'p2'),
  PlanOffer(id: 'pro_monthly', plan: Plan.pro, period: BillingPeriod.monthly, price: 'p3'),
  PlanOffer(id: 'pro_annual', plan: Plan.pro, period: BillingPeriod.annual, price: 'p4'),
];

const _renewalNote =
    'A subscription renews automatically at the end of each period until you cancel it, and the store charges your '
    'store account. You can cancel it in the subscription settings of the store.';

void main() {
  late FakeEntitlements entitlements;
  late FakeExternalLinks links;

  Future<void> pumpPage(WidgetTester tester, {Locale? locale}) async {
    links = FakeExternalLinks();
    await tester.pumpApp(
      const PlansPage(),
      locale: locale,
      repositories: mockRepositories(),
      entitlements: entitlements,
      externalLinks: links,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  setUp(() => entitlements = FakeEntitlements(offerList: _offers.toList()));

  group('PlansPage', () {
    testWidgets('renders PlansView with the plan and the offers of the store', (tester) async {
      await pumpPage(tester);

      expect(find.byType(PlansView), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.byType(FilledButton), findsNWidgets(4));
    });

    testWidgets('opens from its route', (tester) async {
      links = FakeExternalLinks();
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(PlansPage.route()),
            child: const Text('open'),
          ),
        ),
        repositories: mockRepositories(),
        entitlements: entitlements,
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(PlansPage), findsOneWidget);
    });

    testWidgets('shows the plan that the store reports after a purchase, and the product in use', (tester) async {
      await pumpPage(tester);

      await tapButton(tester, find.widgetWithText(FilledButton, 'Subscribe Monthly (p1 per month)'));
      expect(entitlements.purchases, [_offers.first]);
      // The purchase alone does not change the plan.
      expect(find.text('Free'), findsOneWidget);

      entitlements.change(Plan.basic);
      await tester.pumpAndSettle();

      expect(find.text('Basic'), findsNWidgets(2));
      expect(find.widgetWithText(OutlinedButton, 'In use: monthly (p1 per month)'), findsOneWidget);
    });

    testWidgets('shows the period that the person switched to in the subscription management of the store', (
      tester,
    ) async {
      entitlements
        ..plan = Plan.basic
        ..offerList = [
          for (final offer in _offers)
            PlanOffer(
              id: offer.id,
              plan: offer.plan,
              period: offer.period,
              price: offer.price,
              isActive: offer.id == 'basic_monthly',
            ),
        ];
      await pumpPage(tester);
      expect(find.widgetWithText(OutlinedButton, 'In use: monthly (p1 per month)'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Subscribe Yearly (p2 per year)'), findsOneWidget);

      // The store switches the period and keeps the plan, so it reports no change of the plan.
      entitlements.offerList = [
        for (final offer in _offers)
          PlanOffer(
            id: offer.id,
            plan: offer.plan,
            period: offer.period,
            price: offer.price,
            isActive: offer.id == 'basic_annual',
          ),
      ];
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(entitlements.invalidations, 1);
      expect(find.widgetWithText(FilledButton, 'Subscribe Monthly (p1 per month)'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'In use: yearly (p2 per year)'), findsOneWidget);
    });

    // Review Focus 5.
    testWidgets('opens one store sheet for two taps on a purchase control', (tester) async {
      entitlements.purchaseGate = Completer<void>();
      await pumpPage(tester);
      final control = find.widgetWithText(FilledButton, 'Subscribe Yearly (p4 per year)');
      await tester.ensureVisible(control);

      await tester.tap(control);
      await tester.pump();
      await tester.tap(control, warnIfMissed: false);
      await tester.pump();
      entitlements.purchaseGate!.complete();
      await tester.pumpAndSettle();

      expect(entitlements.purchases, hasLength(1));
    });

    // Review Focus 4.
    testWidgets('says that a restore found nothing, and shows Pro after a restore that the store reports', (
      tester,
    ) async {
      await pumpPage(tester);

      await tapButton(tester, find.widgetWithText(OutlinedButton, 'Restore Purchases'));
      expect(find.text('No purchases to restore.'), findsOneWidget);

      entitlements.restoreOutcome = RestoreOutcome.restored;
      await tapButton(tester, find.widgetWithText(OutlinedButton, 'Restore Purchases'));
      entitlements.change(Plan.pro);
      await tester.pumpAndSettle();

      expect(find.text('Your purchases are restored.'), findsOneWidget);
      expect(find.text('Pro'), findsNWidgets(2));
    });

    // Review Focus 1.
    testWidgets('loads the offers again from the retry control', (tester) async {
      entitlements.offerList = [];
      await pumpPage(tester);
      expect(find.byType(FilledButton), findsNothing);

      entitlements.offerList = _offers.toList();
      await tapButton(tester, find.widgetWithText(TextButton, 'Try Again'));

      expect(find.byType(FilledButton), findsNWidgets(4));
    });

    testWidgets('opens the links through the port, and says when one did not open', (tester) async {
      entitlements.management = Uri.parse('https://apps.apple.com/account/subscriptions');
      await pumpPage(tester);

      await tapButton(tester, find.widgetWithText(OutlinedButton, 'Manage Subscription'));
      await tapButton(tester, find.widgetWithText(TextButton, 'Terms of Use'));
      expect(links.opened, [entitlements.management, termsOfUseUrl]);

      links.opens = false;
      await tapButton(tester, find.widgetWithText(TextButton, 'Privacy Policy'));
      expect(find.text("Can't open the page."), findsOneWidget);
    });

    testWidgets('shows no offer in a build that does not sell plans', (tester) async {
      entitlements.sellsPlans = false;
      await pumpPage(tester);

      expect(find.text("Subscriptions aren't available in this version of the app."), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(entitlements.offerCalls, 0);
    });

    group('on a screen 320 pixels wide at the largest text size', () {
      for (final locale in [const Locale('en'), const Locale('ko')]) {
        testWidgets('cuts none of its texts in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();
          final english = locale.languageCode == 'en';
          entitlements
            ..plan = Plan.basic
            ..offerList = [
              PlanOffer(
                id: _offers[0].id,
                plan: Plan.basic,
                period: BillingPeriod.monthly,
                price: 'p1',
                isActive: true,
              ),
              ..._offers.skip(1),
            ]
            ..management = Uri.parse('https://apps.apple.com/account/subscriptions')
            ..purchaseOutcome = PurchaseOutcome.pending;
          await pumpPage(tester, locale: locale);

          final texts = english
              ? [
                  'Current plan',
                  'Keep up to 5 clients.',
                  'Keep as many clients as you need.',
                  "Reports don't show “Report made with Kkomkkomi”.",
                  'In use: monthly (p1 per month)',
                  'Subscribe Yearly (p2 per year)',
                  'Subscribe Monthly (p3 per month)',
                  'Subscribe Yearly (p4 per year)',
                  "Archived clients don't count.",
                  'Restore Purchases',
                  'Manage Subscription',
                  _renewalNote,
                  'Terms of Use',
                  'Privacy Policy',
                ]
              : [
                  '지금 쓰는 요금제',
                  '거래처를 5곳까지 둘 수 있어요.',
                  '거래처를 개수 제한 없이 둘 수 있어요.',
                  '보고서에 ‘꼼꼬미로 작성됨’ 문구가 들어가지 않아요.',
                  '이용 중: 월간 (매달 p1)',
                  '연간 구독하기 (매년 p2)',
                  '월간 구독하기 (매달 p3)',
                  '연간 구독하기 (매년 p4)',
                  '보관한 거래처는 개수에 들어가지 않아요.',
                  '구매 복원하기',
                  '구독 관리하기',
                  '구독은 해지하기 전까지 기간이 끝날 때마다 자동으로 갱신되고, 요금은 스토어 계정으로 결제돼요. 해지는 스토어의 구독 관리에서 할 수 있어요.',
                  '이용약관',
                  '개인정보 처리방침',
                ];
          for (final text in texts) {
            await tester.ensureVisible(find.text(text).first);
            await tester.pumpAndSettle();
            tester.expectWholeText(text);
          }

          await tapButton(tester, find.text(english ? 'Subscribe Yearly (p4 per year)' : '연간 구독하기 (매년 p4)'));
          final pending = english
              ? "The purchase is waiting for approval. Your plan changes once it's approved."
              : '구매가 승인을 기다리고 있어요. 승인되면 요금제가 바뀌어요.';
          await tester.ensureVisible(find.text(pending));
          await tester.pumpAndSettle();
          tester.expectWholeText(pending);
        });

        testWidgets('cuts none of the texts of a failed load and of a build without a store in '
            '${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();
          final english = locale.languageCode == 'en';
          entitlements.offerList = [];
          await pumpPage(tester, locale: locale);

          final failed = english
              ? "Can't load the subscriptions. Check your connection and try again."
              : '구독 상품을 불러오지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.';
          await tester.ensureVisible(find.text(failed));
          await tester.pumpAndSettle();
          tester
            ..expectWholeText(failed)
            ..expectWholeText(english ? 'Keep up to 2 clients.' : '거래처를 2곳까지 둘 수 있어요.')
            ..expectWholeText(
              english ? 'Reports show “Report made with Kkomkkomi” at the bottom.' : '보고서 아래에 ‘꼼꼬미로 작성됨’ 문구가 들어가요.',
            );

          // A new tree makes a new cubit, which reads whether the build sells plans.
          await tester.pumpWidget(const SizedBox());
          entitlements.sellsPlans = false;
          await pumpPage(tester, locale: locale);
          tester.expectWholeText(
            english ? "Subscriptions aren't available in this version of the app." : '이 버전의 앱에서는 요금제를 구독할 수 없어요.',
          );
        });
      }
    });
  });
}
