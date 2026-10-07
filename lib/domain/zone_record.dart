// The domain imports only Dart core libraries, so `@immutable` from
// `package:meta` is not available here. Every field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

// 🌎 Project imports:
import 'package:kkomkkomi/domain/name.dart';
import 'package:kkomkkomi/domain/photo_ref.dart';
import 'package:kkomkkomi/domain/photo_slot.dart';
import 'package:kkomkkomi/domain/photo_source.dart';
import 'package:kkomkkomi/domain/zone_status.dart';

/// What one visit recorded for one zone.
///
/// [zoneName] is copied when the visit starts, so a later rename of the zone does not change a past report.
final class ZoneRecord {
  new({
    required this.zoneId,
    required String zoneName,
    this.beforePhoto,
    this.afterPhoto,
    this.beforePhotoSource = PhotoSource.unknown,
    this.afterPhotoSource = PhotoSource.unknown,
    DateTime? beforeCapturedAt,
    DateTime? afterCapturedAt,
    this.note = '',
    this.status = ZoneStatus.done,
    this.reason = '',
  }) : zoneName = normalizeName(zoneName),
       beforeCapturedAt = beforePhoto != null && beforePhotoSource == PhotoSource.camera
           ? beforeCapturedAt?.toUtc()
           : null,
       afterCapturedAt = afterPhoto != null && afterPhotoSource == PhotoSource.camera ? afterCapturedAt?.toUtc() : null;

  final String zoneId;
  final String zoneName;
  final PhotoRef? beforePhoto;
  final PhotoRef? afterPhoto;
  final PhotoSource beforePhotoSource;
  final PhotoSource afterPhotoSource;

  /// UTC device-clock observations supplied only by an in-app camera. Unknown, gallery and empty slots have none.
  final DateTime? beforeCapturedAt;
  final DateTime? afterCapturedAt;
  final String note;

  /// Whether the visit cleaned the zone as agreed. A record is done unless the person sets an exception.
  final ZoneStatus status;

  /// What is left or why, for an exception, as it is written. A record keeps its reason when its status goes back to
  /// [ZoneStatus.done], so that a status set by mistake loses no text, and every reader of a done record ignores it.
  final String reason;

  /// The photo in [slot], or null when the visit did not take it.
  PhotoRef? photoIn(PhotoSlot slot) => switch (slot) {
    PhotoSlot.before => beforePhoto,
    PhotoSlot.after => afterPhoto,
  };

  /// The observed source of the photo in [slot], or unknown for old records.
  PhotoSource sourceIn(PhotoSlot slot) => switch (slot) {
    PhotoSlot.before => beforePhotoSource,
    PhotoSlot.after => afterPhotoSource,
  };

  DateTime? capturedAtIn(PhotoSlot slot) => switch (slot) {
    PhotoSlot.before => beforeCapturedAt,
    PhotoSlot.after => afterCapturedAt,
  };

  /// The slots that hold no photo, in the order of [PhotoSlot.values].
  List<PhotoSlot> get emptySlots => [
    for (final slot in PhotoSlot.values)
      if (photoIn(slot) == null) slot,
  ];

  /// Whether the note holds text. A note of spaces and line breaks alone holds none.
  bool get hasNote => note.trim().isNotEmpty;

  /// Whether the record holds a photo, a note, or an exception, which is what a report can print for the zone.
  ///
  /// A done record without a photo and without a note was not part of the visit, and a record with an exception
  /// always counts, so that a zone that was not cleaned is never left out of a report.
  bool get hasContent => beforePhoto != null || afterPhoto != null || hasNote || status != ZoneStatus.done;

  /// This record with [photo] in [slot], in place of the photo that it holds there.
  ZoneRecord withPhoto(
    PhotoSlot slot,
    PhotoRef photo, {
    PhotoSource source = PhotoSource.unknown,
    DateTime? capturedAt,
  }) => ZoneRecord(
    zoneId: zoneId,
    zoneName: zoneName,
    beforePhoto: slot == PhotoSlot.before ? photo : beforePhoto,
    afterPhoto: slot == PhotoSlot.after ? photo : afterPhoto,
    beforePhotoSource: slot == PhotoSlot.before ? source : beforePhotoSource,
    afterPhotoSource: slot == PhotoSlot.after ? source : afterPhotoSource,
    beforeCapturedAt: slot == PhotoSlot.before ? capturedAt : beforeCapturedAt,
    afterCapturedAt: slot == PhotoSlot.after ? capturedAt : afterCapturedAt,
    note: note,
    status: status,
    reason: reason,
  );

  /// This record with [note] in place of its note. The note stays as it is written, so it is not trimmed.
  ZoneRecord withNote(String note) => _copy(note: note);

  /// This record with [status] in place of its status. The reason stays, also for [ZoneStatus.done].
  ZoneRecord withStatus(ZoneStatus status) => _copy(status: status);

  /// This record with [reason] in place of its reason. The reason stays as it is written, so it is not trimmed.
  ZoneRecord withReason(String reason) => _copy(reason: reason);

  ZoneRecord _copy({String? note, ZoneStatus? status, String? reason}) => ZoneRecord(
    zoneId: zoneId,
    zoneName: zoneName,
    beforePhoto: beforePhoto,
    afterPhoto: afterPhoto,
    beforePhotoSource: beforePhotoSource,
    afterPhotoSource: afterPhotoSource,
    beforeCapturedAt: beforeCapturedAt,
    afterCapturedAt: afterCapturedAt,
    note: note ?? this.note,
    status: status ?? this.status,
    reason: reason ?? this.reason,
  );

  @override
  bool operator ==(Object other) =>
      other is ZoneRecord &&
      other.zoneId == zoneId &&
      other.zoneName == zoneName &&
      other.beforePhoto == beforePhoto &&
      other.afterPhoto == afterPhoto &&
      other.beforePhotoSource == beforePhotoSource &&
      other.afterPhotoSource == afterPhotoSource &&
      other.beforeCapturedAt == beforeCapturedAt &&
      other.afterCapturedAt == afterCapturedAt &&
      other.note == note &&
      other.status == status &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(
    zoneId,
    zoneName,
    beforePhoto,
    afterPhoto,
    beforePhotoSource,
    afterPhotoSource,
    beforeCapturedAt,
    afterCapturedAt,
    note,
    status,
    reason,
  );
}
