/// Makes the opaque identifiers of new entities, so that tests control them.
abstract interface class IdGenerator {
  /// An identifier that no entity uses.
  String newId();
}
