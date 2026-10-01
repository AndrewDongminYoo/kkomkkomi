/// Tells which user the app runs for, so that tests never start a backend.
abstract interface class Identity {
  /// The ID of the current user, or null while identity is unavailable.
  ///
  /// Identity is unavailable in a flavor that has no backend, and while a sign-in did not work, for example without
  /// a network. A call can start a new sign-in, so a later call can give an ID after an earlier one gave null.
  /// The call does not throw.
  Future<String?> currentUserId();
}
