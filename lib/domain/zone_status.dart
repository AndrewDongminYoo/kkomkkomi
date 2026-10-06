/// Whether a visit cleaned a zone as agreed.
///
/// A zone record is done unless the person sets an exception, which carries a reason that the report shows as the
/// follow-up.
enum ZoneStatus {
  /// The zone was cleaned as agreed.
  done,

  /// Part of the zone was cleaned, and the reason says what is left.
  partlyDone,

  /// The zone was not cleaned, and the reason says why.
  notDone,
}
