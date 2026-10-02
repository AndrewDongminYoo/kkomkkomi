/// Erases what the app stores in its database on the device.
abstract interface class LocalDataRepository {
  /// Deletes every row of every table: the company profile, the clients, their zones, the visits, the client pages,
  /// the publish jobs, the records of uploaded photos, and the open capture. The database is then as a first launch
  /// leaves it.
  ///
  /// The rows go in one transaction, so a failure leaves them all. The space that held them is then rewritten, so
  /// that the deleted data does not stay in the file. A repeated call is no failure.
  Future<void> eraseAll();
}
