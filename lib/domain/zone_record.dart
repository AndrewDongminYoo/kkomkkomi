// The domain imports only Dart core libraries, so `@immutable` from
// `package:meta` is not available here. Every field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:kkomkkomi/domain/name.dart';
import 'package:kkomkkomi/domain/photo_ref.dart';

/// What one visit recorded for one zone.
///
/// [zoneName] is copied when the visit starts, so a later rename of the zone does not change a past report.
final class ZoneRecord {
  new({
    required this.zoneId,
    required String zoneName,
    this.beforePhoto,
    this.afterPhoto,
    this.note = '',
  }) : zoneName = normalizeName(zoneName);

  final String zoneId;
  final String zoneName;
  final PhotoRef? beforePhoto;
  final PhotoRef? afterPhoto;
  final String note;

  @override
  bool operator ==(Object other) =>
      other is ZoneRecord &&
      other.zoneId == zoneId &&
      other.zoneName == zoneName &&
      other.beforePhoto == beforePhoto &&
      other.afterPhoto == afterPhoto &&
      other.note == note;

  @override
  int get hashCode => Object.hash(zoneId, zoneName, beforePhoto, afterPhoto, note);
}
