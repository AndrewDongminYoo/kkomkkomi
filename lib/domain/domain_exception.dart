/// A domain rule that the input of a person broke.
///
/// A value that only a programming error can produce throws an [ArgumentError] instead.
sealed class DomainException implements Exception {
  const new();
}

/// A name was empty after it was trimmed.
final class EmptyNameException extends DomainException {
  const new();
}

/// Two active zones of one client would share [name].
final class DuplicateZoneNameException extends DomainException {
  const new(this.name);

  final String name;
}
