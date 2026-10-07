// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';

/// What became of the name that a person last submitted in a name field.
enum NameEntry {
  /// Nothing was submitted since the field opened.
  editing,

  /// The name is on its way to storage.
  saving,

  /// The domain refused the name, because it is empty after trimming.
  empty,

  /// The domain refused the name, because an active zone of the client has it.
  duplicate,

  /// The plan of the company holds no more active clients, so the client with the name is not saved.
  limitReached,

  /// Storage did not take the name.
  failed,

  /// The name is stored.
  saved;

  /// The entry for a name that the domain refused with [exception].
  static NameEntry refusedBy(DomainException exception) => switch (exception) {
    EmptyNameException() => empty,
    DuplicateZoneNameException() => duplicate,
  };
}
