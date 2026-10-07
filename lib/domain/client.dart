// The domain imports only Dart core libraries, so `@immutable` from
// `package:meta` is not available here. Every field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

// 🌎 Project imports:
import 'package:kkomkkomi/domain/name.dart';

/// A customer of the cleaning company.
///
/// A client is archived and never deleted, because its visits must stay readable.
final class Client {
  new({
    required this.id,
    required String name,
    required DateTime createdAt,
    this.isArchived = false,
  }) : name = normalizeName(name),
       createdAt = createdAt.toUtc();

  final String id;
  final String name;
  final bool isArchived;

  /// The creation time in UTC.
  final DateTime createdAt;

  Client rename(String name) => Client(id: id, name: name, createdAt: createdAt, isArchived: isArchived);

  Client archive() => Client(id: id, name: name, createdAt: createdAt, isArchived: true);

  @override
  bool operator ==(Object other) =>
      other is Client &&
      other.id == id &&
      other.name == name &&
      other.isArchived == isArchived &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, isArchived, createdAt);
}
