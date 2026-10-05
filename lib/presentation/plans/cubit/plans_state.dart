// Every field of the class is final, and `package:meta`, which has `@immutable`, is not a dependency.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

part of 'plans_cubit.dart';

enum PlansStatus {
  /// The plan is on its way from the store.
  loading,

  /// [PlansState.plan] holds the plan that the store gave.
  ready,
}

/// Where the offers are.
enum OffersStatus {
  /// The offers are on their way from the store.
  loading,

  /// [PlansState.offers] holds what the store sells.
  loaded,

  /// The store gave no offers: it did not answer, or nothing is for sale yet.
  failed,
}

/// The outcome of the last action, which the screen shows until the next action.
enum PlansNotice {
  /// The purchase waits for an approval.
  purchasePending,

  /// The purchase did not work.
  purchaseFailed,

  /// The restore found a paid plan.
  restored,

  /// The restore found no paid plan.
  nothingFound,

  /// The restore did not work.
  restoreFailed,

  /// A page outside the app did not open.
  linkFailed,
}

final class PlansState {
  const new({
    required this.sellsPlans,
    this.status = PlansStatus.loading,
    this.plan = Plan.free,
    this.offersStatus = OffersStatus.loading,
    this.offers = const [],
    this.managementUrl,
    this.isBusy = false,
    this.notice,
  });

  /// Whether the build can sell a plan. When it cannot, the screen shows no offer and no purchase control.
  final bool sellsPlans;

  final PlansStatus status;

  /// The plan that the store confirmed. A purchase does not set it: only the store does.
  final Plan plan;

  final OffersStatus offersStatus;

  /// The offers for sale, in the order of the plans.
  final List<PlanOffer> offers;

  /// The store page where the subscription is managed, or null when none is known.
  final Uri? managementUrl;

  /// Whether a purchase or a restore is on its way. The screen takes no touch while it is.
  final bool isBusy;

  /// The outcome of the last action, or null when it needs no message.
  final PlansNotice? notice;

  /// Whether [offer] is the product that grants the current plan, so that buying it again does nothing.
  ///
  /// The plan decides, so that an expiry does not leave an old product in use. When the store named no product of the
  /// current plan as active, both periods of the plan count as in use: a period switch then waits for the store
  /// subscription management, and no second purchase of the product in use reaches the store.
  bool isInUse(PlanOffer offer) {
    if (offer.plan != plan) return false;
    final storeNamedOne = offers.any((other) => other.plan == plan && other.isActive);
    return offer.isActive || !storeNamedOne;
  }

  PlansState copyWith({
    PlansStatus? status,
    Plan? plan,
    OffersStatus? offersStatus,
    List<PlanOffer>? offers,
    Uri? managementUrl,
  }) => PlansState(
    sellsPlans: sellsPlans,
    status: status ?? this.status,
    plan: plan ?? this.plan,
    offersStatus: offersStatus ?? this.offersStatus,
    offers: offers ?? this.offers,
    managementUrl: managementUrl ?? this.managementUrl,
    isBusy: isBusy,
    notice: notice,
  );

  /// This state with [isBusy], and [notice] as the outcome of the last action.
  PlansState withAction({required bool isBusy, PlansNotice? notice}) => PlansState(
    sellsPlans: sellsPlans,
    status: status,
    plan: plan,
    offersStatus: offersStatus,
    offers: offers,
    managementUrl: managementUrl,
    isBusy: isBusy,
    notice: notice,
  );

  @override
  bool operator ==(Object other) =>
      other is PlansState &&
      other.sellsPlans == sellsPlans &&
      other.status == status &&
      other.plan == plan &&
      other.offersStatus == offersStatus &&
      sameElements(other.offers, offers) &&
      other.managementUrl == managementUrl &&
      other.isBusy == isBusy &&
      other.notice == notice;

  @override
  int get hashCode =>
      Object.hash(sellsPlans, status, plan, offersStatus, Object.hashAll(offers), managementUrl, isBusy, notice);
}
