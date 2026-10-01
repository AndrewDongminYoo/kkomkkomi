// The domain imports only Dart core libraries, so `@immutable` from
// `package:meta` is not available here. Every field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:kkomkkomi/domain/domain_exception.dart';
import 'package:kkomkkomi/domain/equality.dart';
import 'package:kkomkkomi/domain/zone.dart';

/// The zones of one client, removed zones included.
///
/// This type owns the rule that two active zones of one client must not share a name.
/// A removed zone does not reserve its name.
final class ClientZones {
  /// Throws a [DuplicateZoneNameException] when two active zones share a name.
  ///
  /// Throws an [ArgumentError] when a zone belongs to another client or when two zones share an identifier.
  new({required this.clientId, Iterable<Zone> zones = const []})
    : all = List.unmodifiable(zones.toList()..sort(_byPosition)) {
    final ids = <String>{};
    final activeNames = <String>{};
    for (final zone in all) {
      if (zone.clientId != clientId) {
        throw ArgumentError.value(zone.clientId, 'zones', 'A zone belongs to another client');
      }
      if (!ids.add(zone.id)) {
        throw ArgumentError.value(zone.id, 'zones', 'Two zones share an identifier');
      }
      if (zone.isActive && !activeNames.add(zone.name)) {
        throw DuplicateZoneNameException(zone.name);
      }
    }
  }

  final String clientId;

  /// Every zone in [Zone.position] order, removed zones included.
  final List<Zone> all;

  /// The zones that are not removed, in [Zone.position] order.
  List<Zone> get active => List.unmodifiable(all.where((zone) => zone.isActive));

  /// Adds an active zone after every zone that exists.
  ///
  /// Throws an [EmptyNameException] or a [DuplicateZoneNameException] when [name] breaks a naming rule.
  ClientZones add({required String id, required String name}) {
    final position = all.isEmpty ? 0 : all.last.position + 1;
    return ClientZones(
      clientId: clientId,
      zones: [
        ...all,
        Zone(id: id, clientId: clientId, name: name, position: position),
      ],
    );
  }

  /// Renames the zone with [zoneId].
  ///
  /// Throws an [EmptyNameException] or a [DuplicateZoneNameException] when [name] breaks a naming rule.
  ClientZones rename(String zoneId, String name) => _replace(zoneId, (zone) => zone.rename(name));

  /// Removes the zone with [zoneId] from [active] and keeps it in [all].
  ClientZones remove(String zoneId) => _replace(zoneId, (zone) => zone.deactivate());

  ClientZones _replace(String zoneId, Zone Function(Zone zone) change) {
    if (!all.any((zone) => zone.id == zoneId)) {
      throw ArgumentError.value(zoneId, 'zoneId', 'The client has no such zone');
    }
    return ClientZones(
      clientId: clientId,
      zones: all.map((zone) => zone.id == zoneId ? change(zone) : zone),
    );
  }

  static int _byPosition(Zone a, Zone b) {
    final byPosition = a.position.compareTo(b.position);
    return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
  }

  @override
  bool operator ==(Object other) => other is ClientZones && other.clientId == clientId && sameElements(other.all, all);

  @override
  int get hashCode => Object.hash(clientId, Object.hashAll(all));
}
