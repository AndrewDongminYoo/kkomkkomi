// The domain imports only Dart core libraries, so `@immutable` from
// `package:meta` is not available here. Every field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:kkomkkomi/domain/client_zones.dart';
import 'package:kkomkkomi/domain/equality.dart';
import 'package:kkomkkomi/domain/visit_date.dart';
import 'package:kkomkkomi/domain/zone_record.dart';

/// One cleaning visit to a client on a date.
///
/// A client can have more than one visit on one date.
final class Visit {
  /// Throws an [ArgumentError] when two of the [zoneRecords] are for the same zone.
  new({
    required this.id,
    required this.clientId,
    required this.visitDate,
    required DateTime createdAt,
    Iterable<ZoneRecord> zoneRecords = const [],
  }) : createdAt = createdAt.toUtc(),
       zoneRecords = List.unmodifiable(zoneRecords) {
    final zoneIds = <String>{};
    for (final record in this.zoneRecords) {
      if (!zoneIds.add(record.zoneId)) {
        throw ArgumentError.value(record.zoneId, 'zoneRecords', 'Two records are for the same zone');
      }
    }
  }

  /// Starts a visit that holds one empty record for each active zone in [zones], in position order.
  factory start({
    required String id,
    required ClientZones zones,
    required VisitDate visitDate,
    required DateTime createdAt,
  }) => Visit(
    id: id,
    clientId: zones.clientId,
    visitDate: visitDate,
    createdAt: createdAt,
    zoneRecords: [for (final zone in zones.active) ZoneRecord(zoneId: zone.id, zoneName: zone.name)],
  );

  final String id;
  final String clientId;
  final VisitDate visitDate;

  /// The creation time in UTC.
  final DateTime createdAt;

  /// The records in the order that the visit shows them.
  final List<ZoneRecord> zoneRecords;

  /// The record for the zone with [zoneId], or null when the visit holds none.
  ZoneRecord? recordFor(String zoneId) {
    for (final record in zoneRecords) {
      if (record.zoneId == zoneId) return record;
    }
    return null;
  }

  /// This visit with [record] in place of the record that it holds for the same zone.
  ///
  /// Throws an [ArgumentError] when the visit holds no record for that zone, because a visit keeps the zones that it
  /// started with.
  Visit withRecord(ZoneRecord record) {
    if (recordFor(record.zoneId) == null) {
      throw ArgumentError.value(record.zoneId, 'record', 'The visit holds no record for this zone');
    }
    return Visit(
      id: id,
      clientId: clientId,
      visitDate: visitDate,
      createdAt: createdAt,
      zoneRecords: [
        for (final held in zoneRecords)
          if (held.zoneId == record.zoneId) record else held,
      ],
    );
  }

  /// Orders visits by [visitDate], and visits on one date by [createdAt].
  int compareChronologically(Visit other) {
    final byDate = visitDate.compareTo(other.visitDate);
    return byDate != 0 ? byDate : createdAt.compareTo(other.createdAt);
  }

  @override
  bool operator ==(Object other) =>
      other is Visit &&
      other.id == id &&
      other.clientId == clientId &&
      other.visitDate == visitDate &&
      other.createdAt == createdAt &&
      sameElements(other.zoneRecords, zoneRecords);

  @override
  int get hashCode => Object.hash(id, clientId, visitDate, createdAt, Object.hashAll(zoneRecords));
}
