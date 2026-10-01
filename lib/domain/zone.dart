// The domain imports only Dart core libraries, so `@immutable` from
// `package:meta` is not available here. Every field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:kkomkkomi/domain/name.dart';

/// An area inside a client site that gets one before/after photo pair per visit.
///
/// A removed zone stays with [isActive] set to false, so that past visits keep their records.
final class Zone {
  new({
    required this.id,
    required this.clientId,
    required String name,
    required this.position,
    this.isActive = true,
  }) : name = normalizeName(name);

  final String id;
  final String clientId;
  final String name;

  /// The place of the zone in the zone list of its client, lowest first.
  final int position;
  final bool isActive;

  Zone rename(String name) => Zone(id: id, clientId: clientId, name: name, position: position, isActive: isActive);

  Zone deactivate() => Zone(id: id, clientId: clientId, name: name, position: position, isActive: false);

  Zone moveTo(int position) => Zone(id: id, clientId: clientId, name: name, position: position, isActive: isActive);

  @override
  bool operator ==(Object other) =>
      other is Zone &&
      other.id == id &&
      other.clientId == clientId &&
      other.name == name &&
      other.position == position &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, clientId, name, position, isActive);
}
