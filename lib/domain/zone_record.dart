// The domain imports only Dart core libraries, so `@immutable` from
// `package:meta` is not available here. Every field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:kkomkkomi/domain/name.dart';
import 'package:kkomkkomi/domain/photo_ref.dart';
import 'package:kkomkkomi/domain/photo_slot.dart';

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

  /// The photo in [slot], or null when the visit did not take it.
  PhotoRef? photoIn(PhotoSlot slot) => switch (slot) {
    PhotoSlot.before => beforePhoto,
    PhotoSlot.after => afterPhoto,
  };

  /// This record with [photo] in [slot], in place of the photo that it holds there.
  ZoneRecord withPhoto(PhotoSlot slot, PhotoRef photo) => ZoneRecord(
    zoneId: zoneId,
    zoneName: zoneName,
    beforePhoto: slot == PhotoSlot.before ? photo : beforePhoto,
    afterPhoto: slot == PhotoSlot.after ? photo : afterPhoto,
    note: note,
  );

  /// This record with [note] in place of its note. The note stays as it is written, so it is not trimmed.
  ZoneRecord withNote(String note) =>
      ZoneRecord(zoneId: zoneId, zoneName: zoneName, beforePhoto: beforePhoto, afterPhoto: afterPhoto, note: note);

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
