/// Tells which user the app runs for, so that tests never start a backend.
abstract interface class Identity {
  /// The ID of the current user, or null while identity is unavailable.
  ///
  /// Identity is unavailable in a flavor that has no backend, and while a sign-in did not work, for example without
  /// a network. A call can start a new sign-in, so a later call can give an ID after an earlier one gave null.
  /// The call does not throw.
  Future<String?> currentUserId();

  /// Deletes the account that the device holds on the backend, and signs out of it.
  ///
  /// Does nothing when the device holds no account, so a repeated call after a deletion is no failure, and it never
  /// signs in. Throws when the backend does not delete the account, for example without a network.
  Future<void> deleteAccount();

  /// Whether a newly issued ID token of the current user holds a paid entitlement (`basic` or `pro`) in its
  /// `revenueCatEntitlements` claim, which the RevenueCat Firebase extension writes and `firestore.rules` reads.
  ///
  /// Gives false without an account, without a network, and for any failure, so a caller falls back to the report
  /// with the footer. The call does not throw.
  Future<bool> hasPaidEntitlement();
}
