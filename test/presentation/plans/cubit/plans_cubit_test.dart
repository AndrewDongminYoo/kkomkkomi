import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

import '../../../helpers/helpers.dart';

const _basicMonthly = PlanOffer(id: 'basic_monthly', plan: Plan.basic, period: BillingPeriod.monthly, price: 'p1');
const _basicAnnual = PlanOffer(id: 'basic_annual', plan: Plan.basic, period: BillingPeriod.annual, price: 'p2');
const _proMonthly = PlanOffer(id: 'pro_monthly', plan: Plan.pro, period: BillingPeriod.monthly, price: 'p3');
const _proAnnual = PlanOffer(id: 'pro_annual', plan: Plan.pro, period: BillingPeriod.annual, price: 'p4');
const List<PlanOffer> _offers = [_basicMonthly, _basicAnnual, _proMonthly, _proAnnual];

final Uri _management = Uri.parse('https://apps.apple.com/account/subscriptions');

void main() {
  late FakeEntitlements entitlements;
  late FakeExternalLinks links;

  setUp(() {
    entitlements = FakeEntitlements(offerList: _offers.toList());
    links = FakeExternalLinks();
  });

  PlansCubit build() => PlansCubit(entitlements: entitlements, links: links);

  const loaded = PlansState(
    sellsPlans: true,
    status: PlansStatus.ready,
    offersStatus: OffersStatus.loaded,
    offers: _offers,
  );

  group('PlansCubit', () {
    test('starts loading, with whether the build sells plans', () {
      expect(build().state, const PlansState(sellsPlans: true));
      entitlements.sellsPlans = false;
      expect(build().state, const PlansState(sellsPlans: false));
    });

    blocTest<PlansCubit, PlansState>(
      'loads the plan, then the offers and the management page',
      setUp: () {
        entitlements
          ..plan = Plan.basic
          ..management = _management;
      },
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => [
        const PlansState(sellsPlans: true, status: PlansStatus.ready, plan: Plan.basic),
        PlansState(
          sellsPlans: true,
          status: PlansStatus.ready,
          plan: Plan.basic,
          offersStatus: OffersStatus.loaded,
          offers: _offers,
          managementUrl: _management,
        ),
      ],
    );

    blocTest<PlansCubit, PlansState>(
      'loads only the plan in a build that does not sell plans',
      setUp: () => entitlements.sellsPlans = false,
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => [const PlansState(sellsPlans: false, status: PlansStatus.ready)],
      verify: (_) => expect(entitlements.offerCalls, 0),
    );

    // Review Focus 1: offline, or no products configured yet.
    blocTest<PlansCubit, PlansState>(
      'tells that the offers did not load when the store gives none, and keeps the plan',
      setUp: () => entitlements
        ..plan = Plan.pro
        ..offerList = [],
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => [
        const PlansState(sellsPlans: true, status: PlansStatus.ready, plan: Plan.pro),
        const PlansState(
          sellsPlans: true,
          status: PlansStatus.ready,
          plan: Plan.pro,
          offersStatus: OffersStatus.failed,
        ),
      ],
    );

    blocTest<PlansCubit, PlansState>(
      'reads the offers again at a retry after they did not load',
      build: build,
      seed: () => const PlansState(sellsPlans: true, status: PlansStatus.ready, offersStatus: OffersStatus.failed),
      act: (cubit) => cubit.retry(),
      expect: () => [
        const PlansState(sellsPlans: true, status: PlansStatus.ready),
        loaded,
      ],
    );

    blocTest<PlansCubit, PlansState>(
      'does nothing at a retry when the offers loaded or an action is on its way',
      build: build,
      seed: () => loaded,
      act: (cubit) async {
        await cubit.retry();
        cubit.emit(
          const PlansState(
            sellsPlans: true,
            status: PlansStatus.ready,
            offersStatus: OffersStatus.failed,
            isBusy: true,
          ),
        );
        await cubit.retry();
      },
      skip: 1,
      expect: () => <PlansState>[],
      verify: (_) => expect(entitlements.offerCalls, 0),
    );

    blocTest<PlansCubit, PlansState>(
      'keeps a plan that the store reported while the read of the plan was on its way',
      setUp: () => entitlements.planGate = Completer<void>(),
      build: build,
      act: (cubit) async {
        final load = cubit.load();
        entitlements.change(Plan.pro);
        await pumpEventQueue();
        entitlements.plan = Plan.free;
        entitlements.planGate!.complete();
        await load;
      },
      verify: (cubit) => expect(cubit.state.plan, Plan.pro),
    );

    group('purchase', () {
      blocTest<PlansCubit, PlansState>(
        'buys the offer and takes the plan only from the store',
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.purchase(_basicMonthly);
          entitlements.change(Plan.basic);
          await pumpEventQueue();
        },
        skip: 2,
        expect: () => [
          loaded.withAction(isBusy: true),
          // The offers that are read again after the purchase are the same, so only the plan of the store changes.
          loaded,
          loaded.copyWith(plan: Plan.basic),
        ],
        verify: (_) => expect(entitlements.purchases, [_basicMonthly]),
      );

      // Review Focus 2.
      blocTest<PlansCubit, PlansState>(
        'changes nothing and says nothing when the person closes the purchase sheet',
        setUp: () => entitlements.purchaseOutcome = PurchaseOutcome.cancelled,
        build: build,
        seed: () => loaded,
        act: (cubit) => cubit.purchase(_proAnnual),
        expect: () => [loaded.withAction(isBusy: true), loaded],
        verify: (_) => expect(entitlements.offerCalls, 0),
      );

      // Review Focus 3.
      blocTest<PlansCubit, PlansState>(
        'says that a pending purchase waits for approval, and keeps the plan',
        setUp: () => entitlements.purchaseOutcome = PurchaseOutcome.pending,
        build: build,
        seed: () => loaded,
        act: (cubit) => cubit.purchase(_proMonthly),
        expect: () => [
          loaded.withAction(isBusy: true),
          loaded.withAction(isBusy: false, notice: PlansNotice.purchasePending, pendingOfferId: 'pro_monthly'),
        ],
      );

      blocTest<PlansCubit, PlansState>(
        'stops saying that a purchase waits for approval when the store reports a new plan',
        setUp: () => entitlements.purchaseOutcome = PurchaseOutcome.pending,
        build: build,
        seed: () => loaded,
        act: (cubit) async {
          // The load follows the reports of the store, and gives the state of the seed again.
          await cubit.load();
          await cubit.purchase(_proMonthly);
          // A report of the plan that the screen shows is no approval, so the message stays.
          entitlements.change(Plan.free);
          await pumpEventQueue();
          entitlements.change(Plan.pro);
          await pumpEventQueue();
        },
        expect: () => [
          loaded.withAction(isBusy: true),
          loaded.withAction(isBusy: false, notice: PlansNotice.purchasePending, pendingOfferId: 'pro_monthly'),
          loaded.copyWith(plan: Plan.pro),
        ],
      );

      // Issue 46: a pending purchase of another plan ends by the rule of the plan, which also drops the record of the
      // pending offer, so that a later read of the offers does not act on it.
      blocTest<PlansCubit, PlansState>(
        'drops the record of the pending offer when a new plan ends the message',
        setUp: () => entitlements
          ..plan = Plan.basic
          ..purchaseOutcome = PurchaseOutcome.pending,
        build: build,
        seed: () => loaded.copyWith(plan: Plan.basic),
        act: (cubit) async {
          await cubit.load();
          await cubit.purchase(_proMonthly);
          // The store did not give the products in use, so no offer is marked, and only the plan tells the approval.
          entitlements.change(Plan.pro);
          await pumpEventQueue();
          entitlements.offerList = [_basicMonthly, _basicAnnual, _activeOf(_proMonthly), _proAnnual];
          await cubit.refresh();
        },
        expect: () => [
          loaded.copyWith(plan: Plan.basic).withAction(isBusy: true),
          loaded
              .copyWith(plan: Plan.basic)
              .withAction(isBusy: false, notice: PlansNotice.purchasePending, pendingOfferId: 'pro_monthly'),
          loaded.copyWith(plan: Plan.pro),
          loaded.copyWith(plan: Plan.pro, offers: [_basicMonthly, _basicAnnual, _activeOf(_proMonthly), _proAnnual]),
        ],
      );

      blocTest<PlansCubit, PlansState>(
        'keeps the notice of another action when the store reports a new plan',
        build: build,
        seed: () => loaded.withAction(isBusy: false, notice: PlansNotice.purchaseFailed),
        act: (cubit) async {
          await cubit.load();
          entitlements.change(Plan.pro);
          await pumpEventQueue();
        },
        expect: () => [loaded.copyWith(plan: Plan.pro).withAction(isBusy: false, notice: PlansNotice.purchaseFailed)],
      );

      blocTest<PlansCubit, PlansState>(
        'says that a failed purchase did not work',
        setUp: () => entitlements.purchaseOutcome = PurchaseOutcome.failed,
        build: build,
        seed: () => loaded,
        act: (cubit) => cubit.purchase(_proMonthly),
        expect: () => [
          loaded.withAction(isBusy: true),
          loaded.withAction(isBusy: false, notice: PlansNotice.purchaseFailed),
        ],
      );

      blocTest<PlansCubit, PlansState>(
        'clears the notice of the last action when a new action starts',
        build: build,
        seed: () => loaded.withAction(isBusy: false, notice: PlansNotice.purchaseFailed),
        act: (cubit) => cubit.purchase(_proMonthly),
        expect: () => [loaded.withAction(isBusy: true), loaded],
      );

      // Review Focus 5.
      blocTest<PlansCubit, PlansState>(
        'opens one purchase sheet for two calls, and none while a restore is on its way',
        setUp: () => entitlements.purchaseGate = Completer<void>(),
        build: build,
        seed: () => loaded,
        act: (cubit) async {
          final first = cubit.purchase(_basicMonthly);
          await cubit.purchase(_basicMonthly);
          await cubit.restore();
          entitlements.purchaseGate!.complete();
          await first;
        },
        verify: (_) {
          expect(entitlements.purchases, [_basicMonthly]);
          expect(entitlements.restores, 0);
        },
      );

      // Review Focus 6.
      blocTest<PlansCubit, PlansState>(
        'does not buy the product that is in use',
        build: build,
        seed: () => PlansState(
          sellsPlans: true,
          status: PlansStatus.ready,
          plan: Plan.basic,
          offersStatus: OffersStatus.loaded,
          offers: [_basicMonthly, _activeOf(_basicAnnual)],
        ),
        act: (cubit) => cubit.purchase(_activeOf(_basicAnnual)),
        expect: () => <PlansState>[],
        verify: (_) => expect(entitlements.purchases, isEmpty),
      );

      blocTest<PlansCubit, PlansState>(
        'buys nothing in a build that does not sell plans',
        setUp: () => entitlements.sellsPlans = false,
        build: build,
        act: (cubit) async {
          await cubit.purchase(_basicMonthly);
          await cubit.restore();
        },
        expect: () => <PlansState>[],
        verify: (_) {
          expect(entitlements.purchases, isEmpty);
          expect(entitlements.restores, 0);
        },
      );

      blocTest<PlansCubit, PlansState>(
        'reads the offers again after a purchase, so that a switch of the period shows the product in use',
        build: build,
        seed: () => loaded.copyWith(
          plan: Plan.basic,
          offers: [_activeOf(_basicMonthly), _basicAnnual, _proMonthly, _proAnnual],
        ),
        act: (cubit) async {
          entitlements.offerList = [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual];
          await cubit.purchase(_basicAnnual);
        },
        expect: () {
          final before = loaded.copyWith(
            plan: Plan.basic,
            offers: [_activeOf(_basicMonthly), _basicAnnual, _proMonthly, _proAnnual],
          );
          final after = loaded.copyWith(
            plan: Plan.basic,
            offers: [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual],
          );
          return [
            before.withAction(isBusy: true),
            // The screen takes touches again only after the offers name the product that was just bought.
            after.withAction(isBusy: true),
            after,
          ];
        },
      );

      blocTest<PlansCubit, PlansState>(
        'counts both periods of the plan as in use when the read after a purchase gives no offers',
        build: build,
        seed: () => loaded.copyWith(
          plan: Plan.basic,
          offers: [_activeOf(_basicMonthly), _basicAnnual, _proMonthly, _proAnnual],
        ),
        act: (cubit) async {
          entitlements.offerList = [];
          await cubit.purchase(_basicAnnual);
          // The product that was just bought is not bought a second time.
          await cubit.purchase(_basicAnnual);
        },
        skip: 1,
        expect: () => [
          loaded.copyWith(plan: Plan.basic).withAction(isBusy: true),
          loaded.copyWith(plan: Plan.basic),
        ],
        verify: (cubit) {
          expect(entitlements.purchases, [_basicAnnual]);
          expect(cubit.state.isInUse(_basicMonthly), isTrue);
          expect(cubit.state.isInUse(_basicAnnual), isTrue);
        },
      );

      blocTest<PlansCubit, PlansState>(
        'keeps the offers that it shows when the read after a purchase gives none',
        build: build,
        seed: () => loaded,
        act: (cubit) async {
          entitlements.offerList = [];
          await cubit.purchase(_basicMonthly);
        },
        expect: () => [loaded.withAction(isBusy: true), loaded],
        verify: (cubit) => expect(entitlements.offerCalls, 1),
      );
    });

    group('restore', () {
      // Review Focus 4.
      blocTest<PlansCubit, PlansState>(
        'says that the restore found nothing',
        build: build,
        seed: () => loaded,
        act: (cubit) => cubit.restore(),
        expect: () => [
          loaded.withAction(isBusy: true),
          loaded.withAction(isBusy: false, notice: PlansNotice.nothingFound),
        ],
      );

      blocTest<PlansCubit, PlansState>(
        'shows Pro after a restore when the store reports it',
        setUp: () => entitlements.restoreOutcome = RestoreOutcome.restored,
        build: build,
        seed: () => loaded,
        act: (cubit) async {
          await cubit.load();
          await cubit.restore();
          entitlements.change(Plan.pro);
          await pumpEventQueue();
        },
        verify: (cubit) {
          expect(cubit.state.plan, Plan.pro);
          expect(cubit.state.notice, PlansNotice.restored);
        },
      );

      // Review Focus 6, after a restore: a period that another device changed keeps the plan, so only the offers
      // tell the product in use.
      blocTest<PlansCubit, PlansState>(
        'takes no touch after a restore until the offers name the product that it found',
        setUp: () => entitlements.restoreOutcome = RestoreOutcome.restored,
        build: build,
        seed: () => loaded.copyWith(
          plan: Plan.basic,
          offers: [_activeOf(_basicMonthly), _basicAnnual, _proMonthly, _proAnnual],
        ),
        act: (cubit) async {
          entitlements.offerList = [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual];
          await cubit.restore();
        },
        expect: () {
          final before = loaded.copyWith(
            plan: Plan.basic,
            offers: [_activeOf(_basicMonthly), _basicAnnual, _proMonthly, _proAnnual],
          );
          final after = loaded.copyWith(
            plan: Plan.basic,
            offers: [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual],
          );
          return [
            before.withAction(isBusy: true),
            after.withAction(isBusy: true),
            after.withAction(isBusy: false, notice: PlansNotice.restored),
          ];
        },
      );

      blocTest<PlansCubit, PlansState>(
        'counts both periods of the plan as in use when the read after a restore gives no offers',
        setUp: () => entitlements.restoreOutcome = RestoreOutcome.restored,
        build: build,
        seed: () => loaded.copyWith(
          plan: Plan.basic,
          offers: [_activeOf(_basicMonthly), _basicAnnual, _proMonthly, _proAnnual],
        ),
        act: (cubit) async {
          entitlements.offerList = [];
          await cubit.restore();
          await cubit.purchase(_basicAnnual);
        },
        skip: 1,
        expect: () => [
          loaded.copyWith(plan: Plan.basic).withAction(isBusy: true),
          loaded.copyWith(plan: Plan.basic).withAction(isBusy: false, notice: PlansNotice.restored),
        ],
        verify: (_) => expect(entitlements.purchases, isEmpty),
      );

      blocTest<PlansCubit, PlansState>(
        'says that the restore did not work',
        setUp: () => entitlements.restoreOutcome = RestoreOutcome.failed,
        build: build,
        seed: () => loaded,
        act: (cubit) => cubit.restore(),
        expect: () => [
          loaded.withAction(isBusy: true),
          loaded.withAction(isBusy: false, notice: PlansNotice.restoreFailed),
        ],
      );
    });

    group('links', () {
      blocTest<PlansCubit, PlansState>(
        'opens the management page, and opens nothing when none is known',
        build: build,
        seed: () => loaded,
        act: (cubit) async {
          await cubit.openManagement();
          cubit.emit(loaded.copyWith(managementUrl: () => _management));
          await cubit.openManagement();
        },
        verify: (_) => expect(links.opened, [_management]),
      );

      blocTest<PlansCubit, PlansState>(
        'opens a link and says nothing when it opens',
        build: build,
        seed: () => loaded,
        act: (cubit) => cubit.open(termsOfUseUrl),
        expect: () => <PlansState>[],
        verify: (_) => expect(links.opened, [termsOfUseUrl]),
      );

      blocTest<PlansCubit, PlansState>(
        'says that a link did not open',
        setUp: () => links.opens = false,
        build: build,
        seed: () => loaded,
        act: (cubit) => cubit.open(termsOfUseUrl),
        expect: () => [loaded.withAction(isBusy: false, notice: PlansNotice.linkFailed)],
      );

      blocTest<PlansCubit, PlansState>(
        'keeps taking no touch when a link does not open while a purchase is on its way',
        build: build,
        seed: () => loaded,
        act: (cubit) async {
          links
            ..opens = false
            ..gate = Completer<void>();
          entitlements.purchaseGate = Completer<void>();
          final open = cubit.open(termsOfUseUrl);
          final purchase = cubit.purchase(_proMonthly);
          links.gate!.complete();
          await open;
          // The purchase sheet is still open, so a second purchase opens none.
          await cubit.purchase(_proMonthly);
          entitlements.purchaseGate!.complete();
          await purchase;
        },
        expect: () => [
          loaded.withAction(isBusy: true),
          loaded.withAction(isBusy: true, notice: PlansNotice.linkFailed),
          loaded,
        ],
        verify: (_) => expect(entitlements.purchases, [_proMonthly]),
      );

      blocTest<PlansCubit, PlansState>(
        'reads nothing when the management page opens, because the person changes the subscription after that',
        build: build,
        seed: () => loaded.copyWith(managementUrl: () => _management),
        act: (cubit) => cubit.openManagement(),
        expect: () => <PlansState>[],
        verify: (_) {
          expect(links.opened, [_management]);
          expect(entitlements.offerCalls, 0);
        },
      );

      blocTest<PlansCubit, PlansState>(
        'opens no link while an action is on its way',
        build: build,
        seed: () => loaded.withAction(isBusy: true),
        act: (cubit) => cubit.open(termsOfUseUrl),
        verify: (_) => expect(links.opened, isEmpty),
      );
    });

    group('refresh', () {
      final basicMonthlyInUse = loaded.copyWith(
        plan: Plan.basic,
        offers: [_activeOf(_basicMonthly), _basicAnnual, _proMonthly, _proAnnual],
      );
      final basicAnnualInUse = loaded.copyWith(
        plan: Plan.basic,
        offers: [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual],
      );

      // A switch of the period in the subscription management of the store keeps the plan, so the store reports no
      // change of the plan.
      blocTest<PlansCubit, PlansState>(
        'reads the offers again, so that a switch of the period outside the app shows the product in use',
        build: build,
        seed: () => basicMonthlyInUse,
        act: (cubit) async {
          entitlements
            ..plan = Plan.basic
            ..offerList = [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual];
          await cubit.refresh();
        },
        expect: () => [basicAnnualInUse],
        verify: (cubit) {
          expect(entitlements.invalidations, 1);
          expect(cubit.state.isInUse(_basicMonthly), isFalse);
          expect(cubit.state.isInUse(_activeOf(_basicAnnual)), isTrue);
        },
      );

      blocTest<PlansCubit, PlansState>(
        'drops the kept answers of the store before it reads the plan and the offers',
        build: build,
        seed: () => loaded,
        act: (cubit) async {
          entitlements.invalidateGate = Completer<void>();
          final refresh = cubit.refresh();
          await pumpEventQueue();
          expect(entitlements.calls, 0);
          expect(entitlements.offerCalls, 0);
          entitlements.invalidateGate!.complete();
          await refresh;
        },
        verify: (_) {
          expect(entitlements.calls, 1);
          expect(entitlements.offerCalls, 1);
        },
      );

      blocTest<PlansCubit, PlansState>(
        'takes a plan that changed outside the app, also when the store reported no change',
        build: build,
        seed: () => basicMonthlyInUse,
        act: (cubit) async {
          entitlements
            ..plan = Plan.pro
            ..offerList = [_basicMonthly, _basicAnnual, _activeOf(_proMonthly), _proAnnual];
          await cubit.refresh();
        },
        verify: (cubit) {
          expect(cubit.state.plan, Plan.pro);
          expect(cubit.state.isInUse(_activeOf(_proMonthly)), isTrue);
          expect(cubit.state.isInUse(_basicMonthly), isFalse);
        },
      );

      blocTest<PlansCubit, PlansState>(
        'keeps a plan that the store reported while the read of the plan was on its way',
        build: build,
        seed: () => loaded,
        act: (cubit) async {
          await cubit.load();
          entitlements.planGate = Completer<void>();
          final refresh = cubit.refresh();
          await pumpEventQueue();
          entitlements.change(Plan.pro);
          await pumpEventQueue();
          entitlements.plan = Plan.free;
          entitlements.planGate!.complete();
          await refresh;
        },
        verify: (cubit) => expect(cubit.state.plan, Plan.pro),
      );

      blocTest<PlansCubit, PlansState>(
        'stops showing the management page when the store no longer gives one',
        build: build,
        seed: () => loaded.copyWith(plan: Plan.basic, managementUrl: () => _management),
        act: (cubit) async {
          // The subscription expired outside the app.
          entitlements
            ..plan = Plan.free
            ..management = null;
          await cubit.refresh();
        },
        expect: () => [loaded.copyWith(plan: Plan.basic), loaded],
      );

      // Issue 46: no answer of the store is no sign that the subscription ended.
      blocTest<PlansCubit, PlansState>(
        'keeps the management page when the store does not answer for it',
        build: build,
        seed: () => basicMonthlyInUse.copyWith(managementUrl: () => _management),
        act: (cubit) async {
          entitlements
            ..plan = Plan.basic
            ..offerList = [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual]
            ..managementFails = true;
          await cubit.refresh();
        },
        expect: () => [basicAnnualInUse.copyWith(managementUrl: () => _management)],
      );

      // Issue 46: a switch of the period keeps the plan, so only the offers tell that the store approved it.
      blocTest<PlansCubit, PlansState>(
        'stops saying that a purchase waits for approval when the read marks its offer as active',
        setUp: () => entitlements
          ..plan = Plan.basic
          ..purchaseOutcome = PurchaseOutcome.pending,
        build: build,
        seed: () => basicMonthlyInUse,
        act: (cubit) async {
          await cubit.purchase(_basicAnnual);
          entitlements.offerList = [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual];
          await cubit.refresh();
        },
        expect: () => [
          basicMonthlyInUse.withAction(isBusy: true),
          basicMonthlyInUse.withAction(
            isBusy: false,
            notice: PlansNotice.purchasePending,
            pendingOfferId: 'basic_annual',
          ),
          basicAnnualInUse,
        ],
      );

      blocTest<PlansCubit, PlansState>(
        'keeps saying that a purchase waits for approval when the read fails or does not mark its offer',
        setUp: () => entitlements.plan = Plan.basic,
        build: build,
        seed: () => basicMonthlyInUse.withAction(
          isBusy: false,
          notice: PlansNotice.purchasePending,
          pendingOfferId: 'basic_annual',
        ),
        act: (cubit) async {
          entitlements
            ..offerList = []
            ..managementFails = true;
          await cubit.refresh();
          // The store did not give the products in use, so it marked no offer.
          entitlements.offerList = _offers.toList();
          await cubit.refresh();
        },
        expect: () => [
          loaded
              .copyWith(plan: Plan.basic)
              .withAction(isBusy: false, notice: PlansNotice.purchasePending, pendingOfferId: 'basic_annual'),
        ],
      );

      blocTest<PlansCubit, PlansState>(
        'stops saying that a purchase waits for approval when the read finds a new plan',
        build: build,
        seed: () => loaded.withAction(isBusy: false, notice: PlansNotice.purchasePending),
        act: (cubit) async {
          entitlements.plan = Plan.pro;
          await cubit.refresh();
        },
        expect: () => [loaded.copyWith(plan: Plan.pro)],
      );

      blocTest<PlansCubit, PlansState>(
        'reads nothing before the plan loaded, or while an action is on its way',
        build: build,
        act: (cubit) async {
          await cubit.refresh();
          cubit.emit(loaded.withAction(isBusy: true));
          await cubit.refresh();
        },
        skip: 1,
        expect: () => <PlansState>[],
        verify: (_) {
          expect(entitlements.invalidations, 0);
          expect(entitlements.calls, 0);
          expect(entitlements.offerCalls, 0);
        },
      );

      blocTest<PlansCubit, PlansState>(
        'reads nothing in a build that does not sell plans',
        setUp: () => entitlements.sellsPlans = false,
        build: build,
        seed: () => const PlansState(sellsPlans: false, status: PlansStatus.ready),
        act: (cubit) => cubit.refresh(),
        expect: () => <PlansState>[],
        verify: (_) {
          expect(entitlements.invalidations, 0);
          expect(entitlements.calls, 0);
        },
      );
    });

    blocTest<PlansCubit, PlansState>(
      'follows the plan that the store reports, and reads the offers again',
      build: build,
      act: (cubit) async {
        await cubit.load();
        entitlements
          ..offerList = [_activeOf(_proMonthly)]
          ..change(Plan.pro);
        await pumpEventQueue();
      },
      skip: 2,
      expect: () => [
        loaded.copyWith(plan: Plan.pro),
        loaded.copyWith(plan: Plan.pro, offers: [_activeOf(_proMonthly)]),
      ],
    );

    blocTest<PlansCubit, PlansState>(
      'stops showing the management page when the store reports an expiry and gives no page',
      setUp: () => entitlements
        ..plan = Plan.basic
        ..management = _management,
      build: build,
      act: (cubit) async {
        await cubit.load();
        entitlements
          ..management = null
          ..change(Plan.free);
        await pumpEventQueue();
      },
      skip: 2,
      expect: () => [loaded.copyWith(managementUrl: () => _management), loaded],
    );

    blocTest<PlansCubit, PlansState>(
      'keeps the answer of the newest read of the offers when an older read answers later',
      build: build,
      seed: () => loaded,
      act: (cubit) async {
        await cubit.load();
        final older = Completer<void>();
        entitlements.offerGates.add(older);
        // A report of the plan starts a read before the store knows of the purchase.
        entitlements.change(Plan.free);
        await pumpEventQueue();
        entitlements.offerList = [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual];
        await cubit.purchase(_basicAnnual);
        older.complete();
        await pumpEventQueue();
      },
      expect: () {
        final after = loaded.copyWith(offers: [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual]);
        return [loaded.withAction(isBusy: true), after.withAction(isBusy: true), after];
      },
    );

    blocTest<PlansCubit, PlansState>(
      'waits for a newer read of the offers that starts while the read after a purchase is on its way',
      build: build,
      seed: () => loaded,
      act: (cubit) async {
        await cubit.load();
        final afterPurchase = Completer<void>();
        final newer = Completer<void>();
        entitlements
          ..offerGates.addAll([afterPurchase, newer])
          ..purchaseGate = Completer<void>();
        final purchase = cubit.purchase(_basicAnnual);
        entitlements.purchaseGate!.complete();
        await pumpEventQueue();
        // The store reports the purchase after the read that follows it started.
        entitlements
          ..offerList = [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual]
          ..change(Plan.basic);
        await pumpEventQueue();
        afterPurchase.complete();
        await pumpEventQueue();
        newer.complete();
        await purchase;
      },
      expect: () {
        final after = loaded.copyWith(
          plan: Plan.basic,
          offers: [_basicMonthly, _activeOf(_basicAnnual), _proMonthly, _proAnnual],
        );
        // The read after the purchase gave the offers from before it, and the newer read replaced its answer, so the
        // screen takes touches again only with the answer of the newer read.
        return [
          loaded.withAction(isBusy: true),
          loaded.copyWith(plan: Plan.basic).withAction(isBusy: true),
          after.withAction(isBusy: true),
          after,
        ];
      },
    );

    blocTest<PlansCubit, PlansState>(
      'does not read the offers at a report of the plan while they load',
      build: build,
      seed: () => const PlansState(sellsPlans: true, status: PlansStatus.ready),
      act: (cubit) async {
        // The subscription starts with a load, which the gate holds before it reads the offers.
        entitlements.planGate = Completer<void>();
        unawaited(cubit.load());
        await pumpEventQueue();
        entitlements.change(Plan.basic);
        await pumpEventQueue();
      },
      expect: () => [const PlansState(sellsPlans: true, status: PlansStatus.ready, plan: Plan.basic)],
      verify: (_) => expect(entitlements.offerCalls, 0),
    );

    test('stops following the plan when it closes', () async {
      final cubit = build();
      await cubit.load();
      await cubit.close();

      entitlements.change(Plan.pro);
      await pumpEventQueue();

      expect(cubit.state.plan, Plan.free);
    });

    test('changes nothing when it closes while the store answers', () async {
      entitlements
        ..purchaseGate = Completer<void>()
        ..restoreGate = Completer<void>()
        ..planGate = Completer<void>();
      final purchasing = build()..emit(loaded);
      final purchase = purchasing.purchase(_basicMonthly);
      await purchasing.close();
      entitlements.purchaseGate!.complete();
      await purchase;

      final restoring = build()..emit(loaded);
      final restore = restoring.restore();
      await restoring.close();
      entitlements.restoreGate!.complete();
      await restore;

      final loading = build();
      final load = loading.load();
      await loading.close();
      entitlements.planGate!.complete();
      await load;

      links
        ..opens = false
        ..gate = Completer<void>();
      final opening = build()..emit(loaded);
      final open = opening.open(termsOfUseUrl);
      await opening.close();
      links.gate!.complete();
      await open;

      expect(purchasing.state, loaded.withAction(isBusy: true));
      expect(restoring.state, loaded.withAction(isBusy: true));
      expect(loading.state.status, PlansStatus.loading);
      expect(opening.state, loaded);
    });

    test('changes nothing when it closes while a refresh drops the kept answers or reads the plan', () async {
      entitlements
        ..plan = Plan.pro
        ..invalidateGate = Completer<void>();
      final invalidating = build()..emit(loaded);
      final invalidation = invalidating.refresh();
      await invalidating.close();
      entitlements.invalidateGate!.complete();
      await invalidation;

      entitlements
        ..invalidateGate = null
        ..planGate = Completer<void>();
      final reading = build()..emit(loaded);
      final read = reading.refresh();
      await pumpEventQueue();
      await reading.close();
      entitlements.planGate!.complete();
      await read;

      expect(invalidating.state, loaded);
      expect(entitlements.calls, 1);
      expect(reading.state, loaded);
    });

    group('isInUse', () {
      test('is the product that the store named, for the current plan only', () {
        final state = PlansState(
          sellsPlans: true,
          plan: Plan.basic,
          offers: [_basicMonthly, _activeOf(_basicAnnual), _proMonthly],
        );

        expect(state.isInUse(_basicMonthly), isFalse);
        expect(state.isInUse(_activeOf(_basicAnnual)), isTrue);
        expect(state.isInUse(_proMonthly), isFalse);
        expect(state.copyWith(plan: Plan.free).isInUse(_activeOf(_basicAnnual)), isFalse);
      });

      test('is each period of the current plan when the store named no product of it', () {
        const state = PlansState(sellsPlans: true, plan: Plan.pro, offers: _offers);

        expect(state.isInUse(_proMonthly), isTrue);
        expect(state.isInUse(_proAnnual), isTrue);
        expect(state.isInUse(_basicMonthly), isFalse);
      });
    });

    test('a state equals one with the same values only', () {
      final states = [
        loaded,
        loaded.copyWith(status: PlansStatus.loading),
        loaded.copyWith(plan: Plan.pro),
        loaded.copyWith(offersStatus: OffersStatus.failed),
        loaded.copyWith(offers: [_basicMonthly]),
        loaded.copyWith(managementUrl: () => _management),
        loaded.withAction(isBusy: true),
        loaded.withAction(isBusy: false, notice: PlansNotice.restored),
        loaded.withAction(isBusy: false, notice: PlansNotice.purchasePending),
        loaded.withAction(isBusy: false, notice: PlansNotice.purchasePending, pendingOfferId: 'basic_annual'),
        const PlansState(sellsPlans: false),
      ];
      for (final (index, state) in states.indexed) {
        for (final (otherIndex, other) in states.indexed) {
          expect(state == other, index == otherIndex, reason: '$index and $otherIndex');
        }
      }
      expect(loaded.hashCode, loaded.copyWith().hashCode);
    });

    test('a copy keeps the pending offer unless it is given, and a new action drops it', () {
      final pending = loaded.withAction(
        isBusy: false,
        notice: PlansNotice.purchasePending,
        pendingOfferId: 'basic_annual',
      );

      expect(pending.copyWith(plan: Plan.pro).pendingOfferId, 'basic_annual');
      expect(pending.copyWith(pendingOfferId: () => null).pendingOfferId, isNull);
      expect(pending.withAction(isBusy: true).pendingOfferId, isNull);
    });
  });
}

PlanOffer _activeOf(PlanOffer offer) =>
    PlanOffer(id: offer.id, plan: offer.plan, period: offer.period, price: offer.price, isActive: true);
