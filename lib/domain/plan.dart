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
}
