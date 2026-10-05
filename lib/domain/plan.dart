/// The plan of a company, from the entitlements that the store confirmed.
enum Plan {
  /// The plan without a subscription.
  free,

  /// The plan that the entitlement `basic` grants.
  basic,

  /// The plan that the entitlement `pro` grants. A Pro product grants `basic` too.
  pro;

  /// The plan that the active entitlement identifiers grant. `pro` wins over `basic`, and other identifiers grant
  /// nothing.
  static Plan fromEntitlements(Iterable<String> activeIds) {
    final ids = activeIds.toSet();
    if (ids.contains('pro')) return Plan.pro;
    if (ids.contains('basic')) return Plan.basic;
    return Plan.free;
  }

  /// Whether the plan is one that the company pays for.
  bool get isPaid => this != Plan.free;

  /// The most active clients that the plan holds, or null when the plan has no limit. Archived clients do not count.
  int? get clientLimit => switch (this) {
    Plan.free => 2,
    Plan.basic => 5,
    Plan.pro => null,
  };

  /// Whether a company of the plan with [activeClients] active clients may add one more. A company at or above the
  /// limit, for example after a downgrade, keeps its clients and may not add one.
  bool allowsAnotherClient(int activeClients) => switch (clientLimit) {
    final limit? => activeClients < limit,
    null => true,
  };

  /// Whether a report of the plan carries the footer text. Only the Free plan prints it.
  bool get showsFooter => this == Plan.free;
}

/// How often a paid plan renews.
enum BillingPeriod {
  /// The subscription renews each month.
  monthly,

  /// The subscription renews each year.
  annual,
}
