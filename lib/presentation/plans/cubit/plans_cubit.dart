import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

part 'plans_state.dart';

/// Loads the plan and the offers, follows the plan that the store reports, and buys, restores, and opens the store
/// subscription management.
class PlansCubit extends Cubit<PlansState> {
  new({required this._entitlements, required this._links}) : super(PlansState(sellsPlans: _entitlements.sellsPlans));

  final Entitlements _entitlements;
  final ExternalLinks _links;

  StreamSubscription<Plan>? _planChanges;

  /// How many plans the store reported, so that a read of the plan can tell whether a report came during it.
  int _planReports = 0;

  /// How many reads of the offers started. Only the read that started last changes the state.
  int _reads = 0;

  /// The read of the offers that started last.
  late Future<bool> _newestRead;

  /// Reads the plan, and the offers and the management page when the build sells plans, and follows the plan that
  /// the store reports from then on.
  Future<void> load() async {
    _planChanges ??= _entitlements.planChanges.listen(_onPlan);
    final plan = await _entitlements.currentPlan();
    if (isClosed) return;
    // A plan that the store reported while the read was on its way is newer than the answer of the read.
    emit(state.copyWith(status: PlansStatus.ready, plan: state.status == PlansStatus.ready ? null : plan));
    if (state.sellsPlans) await _loadOffers();
  }

  /// Reads the offers again after they did not load. A call while the offers load or an action is on its way does
  /// nothing.
  Future<void> retry() async {
    if (state.offersStatus != OffersStatus.failed || state.isBusy) return;
    emit(state.copyWith(offersStatus: OffersStatus.loading));
    await _loadOffers();
  }

  /// Opens the purchase sheet of the store for [offer].
  ///
  /// The plan changes only when the store reports it. A call while an action is on its way, or for the product that
  /// is in use, does nothing, so that no second purchase sheet opens.
  Future<void> purchase(PlanOffer offer) async {
    if (state.isBusy || !state.sellsPlans || state.isInUse(offer)) return;
    emit(state.withAction(isBusy: true));
    final outcome = await _entitlements.purchase(offer);
    if (isClosed) return;
    // A switch of the period keeps the plan, so the store reports no change, and only the offers tell the product in
    // use. The screen takes no touch until they are read again, so that the product that was just bought is not
    // bought a second time.
    if (outcome == PurchaseOutcome.purchased) {
      await _refreshAfterAction();
      if (isClosed) return;
    }
    emit(
      state.withAction(
        isBusy: false,
        notice: switch (outcome) {
          // The plan that the store reports is the message of a purchase, and a person who closed the sheet needs
          // none.
          PurchaseOutcome.purchased || PurchaseOutcome.cancelled => null,
          PurchaseOutcome.pending => PlansNotice.purchasePending,
          PurchaseOutcome.failed => PlansNotice.purchaseFailed,
        },
        pendingOfferId: outcome == PurchaseOutcome.pending ? offer.id : null,
      ),
    );
  }

  /// Asks the store for the purchases of its account. A call while an action is on its way does nothing.
  Future<void> restore() async {
    if (state.isBusy || !state.sellsPlans) return;
    emit(state.withAction(isBusy: true));
    final outcome = await _entitlements.restore();
    if (isClosed) return;
    // A restore can find another period of the current plan, which the store reports as no change of the plan. As
    // after a purchase, the screen takes no touch until the offers name the product that the restore found.
    if (outcome == RestoreOutcome.restored) {
      await _refreshAfterAction();
      if (isClosed) return;
    }
    emit(
      state.withAction(
        isBusy: false,
        notice: switch (outcome) {
          RestoreOutcome.restored => PlansNotice.restored,
          RestoreOutcome.nothingFound => PlansNotice.nothingFound,
          RestoreOutcome.failed => PlansNotice.restoreFailed,
        },
      ),
    );
  }

  /// Reads the plan and the offers again from the store, for a change that the store made outside the app. The screen
  /// calls it each time that the app comes back to the foreground, for example from the subscription management of
  /// the store, where a switch of the period keeps the plan, so that the store reports no change of the plan and only
  /// the offers tell the product in use.
  ///
  /// A call before the plan loaded, in a build that does not sell plans, or while an action is on its way does
  /// nothing: the load reads both, and an action reads the offers again when it ends.
  Future<void> refresh() async {
    if (state.status != PlansStatus.ready || !state.sellsPlans || state.isBusy) return;
    final reports = _planReports;
    await _entitlements.invalidate();
    if (isClosed) return;
    final (plan, _) = await (_entitlements.currentPlan(), _refreshOffers()).wait;
    // A plan that the store reported while the read was on its way is newer than the answer of the read.
    if (isClosed || reports != _planReports) return;
    _takePlan(plan);
  }

  /// Opens the store page where the subscription is managed, when one is known. The open answers when the store page
  /// opens, before the person changes anything there, so [refresh] reads the change when the app comes back.
  Future<void> openManagement() async {
    if (state.managementUrl case final url?) await open(url);
  }

  /// Opens [uri] outside the app, and tells when it did not open.
  Future<void> open(Uri uri) async {
    if (state.isBusy) return;
    final opened = await _links.open(uri);
    if (isClosed || opened) return;
    // A purchase or a restore can start while the link opens, and the screen takes no touch until it ends.
    emit(state.withAction(isBusy: state.isBusy, notice: PlansNotice.linkFailed));
  }

  Future<void> _loadOffers() => _readOffers(isLoad: true);

  /// Reads the offers and the management page again without showing a load, and keeps what the screen shows when
  /// the store does not answer. Answers whether the store gave offers.
  Future<bool> _refreshOffers() {
    if (!state.sellsPlans || state.offersStatus == OffersStatus.loading) return Future.value(false);
    return _readOffers(isLoad: false);
  }

  /// Reads the offers again after the store took a purchase or a restore. Without an answer, the offers still name the
  /// product from before the action. So none stays marked, and both periods of the current plan count as in use.
  Future<void> _refreshAfterAction() async {
    if (await _refreshOffers() || isClosed) return;
    emit(
      state.copyWith(
        offers: [
          for (final offer in state.offers)
            PlanOffer(id: offer.id, plan: offer.plan, period: offer.period, price: offer.price),
        ],
      ),
    );
  }

  /// Starts a read of the offers, which replaces the reads that started before it. A read that a later one replaced
  /// answers with that read.
  Future<bool> _readOffers({required bool isLoad}) =>
      _newestRead = _read(++_reads, isLoad: isLoad).then((answer) => answer ?? _newestRead);

  /// Reads the offers, and answers null when a read that started later replaced this one.
  Future<bool?> _read(int read, {required bool isLoad}) async {
    final (offers, link) = await (_entitlements.offers(), _entitlements.managementUrl()).wait;
    if (isClosed) return false;
    // A read that started later holds a newer answer of the store, for example the one after a purchase, so this one
    // changes nothing.
    if (read != _reads) return null;
    // The store gives no management page when no subscription is left, for example after an expiry, so a known answer
    // replaces the page from before also when it has none. Without an answer of the store, the page from before stays.
    final managementUrl = link.isKnown ? () => link.url : null;
    final next = isLoad
        ? state.copyWith(
            offersStatus: offers.isEmpty ? OffersStatus.failed : OffersStatus.loaded,
            offers: offers,
            managementUrl: managementUrl,
          )
        : state.copyWith(
            offersStatus: offers.isEmpty ? null : OffersStatus.loaded,
            offers: offers.isEmpty ? null : offers,
            managementUrl: managementUrl,
          );
    // The store marks the offer of a purchase that waited for an approval as active once it is approved, also when the
    // plan stays, for example at a switch of the period, so its message no longer applies.
    final approved = offers.any((offer) => offer.id == next.pendingOfferId && offer.isActive);
    emit(approved ? next.withAction(isBusy: next.isBusy) : next);
    return offers.isNotEmpty;
  }

  void _onPlan(Plan plan) {
    if (isClosed) return;
    _planReports++;
    _takePlan(plan);
    unawaited(_refreshOffers());
  }

  /// Shows [plan] as the plan that the store confirmed.
  void _takePlan(Plan plan) {
    final next = state.copyWith(status: PlansStatus.ready, plan: plan);
    // A new plan is the answer to a purchase that waited for an approval, so its message and the record of its offer
    // no longer apply.
    final approved = state.notice == PlansNotice.purchasePending && plan != state.plan;
    emit(approved ? next.withAction(isBusy: next.isBusy) : next);
  }

  @override
  Future<void> close() async {
    await _planChanges?.cancel();
    await super.close();
  }
}
