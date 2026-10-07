// `lib/export/` imports only the domain and `package:pdf`, so `@immutable` from `package:meta` is not available
// here. Every field of each class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:kkomkkomi/domain/domain.dart';

/// What the completion report of one visit prints, before any layout.
///
/// The preview on the report screen and the PDF both show this document, so they hold the same zones.
final class ReportDocument {
  new({
    required this.companyName,
    required this.clientName,
    required this.visitDate,
    required Iterable<ReportZone> zones,
    this.companyPhone = '',
  }) : zones = List.unmodifiable(zones);

  /// The report of [visit], which is a visit to [client] by the company of [companyProfile].
  ///
  /// The zones are in the order of the visit. A zone record without a photo and without a note is left out.
  /// Throws an [ArgumentError] when [visit] is a visit to another client.
  factory fromVisit({required Visit visit, required Client client, required CompanyProfile? companyProfile}) {
    if (visit.clientId != client.id) {
      throw ArgumentError.value(client.id, 'client', 'The visit is a visit to another client');
    }
    return ReportDocument(
      companyName: companyProfile?.name,
      companyPhone: companyProfile?.phone ?? '',
      clientName: client.name,
      visitDate: visit.visitDate,
      zones: [
        for (final record in visit.zoneRecords)
          if (record.hasContent) ReportZone.fromRecord(record),
      ],
    );
  }

  /// The name of the cleaning company, or null when no company profile is saved. A report without it has no
  /// company line.
  final String? companyName;
  final String companyPhone;
  final String clientName;
  final VisitDate visitDate;

  /// The zones that the report prints, in order.
  final List<ReportZone> zones;

  /// Every photo that the report prints, in the order of the zones, the before photo of a zone first.
  List<PhotoRef> get photos => [
    for (final zone in zones) ...[?zone.beforePhoto, ?zone.afterPhoto],
  ];

  /// The number of zones that the visit cleaned as agreed. The summary of a report counts it against the number of
  /// [zones].
  int get doneCount => zones.where((zone) => zone.status == ZoneStatus.done).length;

  /// The zones that the visit did not clean as agreed, in the order of the zones. The summary of a report lists each
  /// with its reason, which is the follow-up.
  List<ReportZone> get exceptions => [
    for (final zone in zones)
      if (zone.status != ZoneStatus.done) zone,
  ];

  @override
  bool operator ==(Object other) =>
      other is ReportDocument &&
      other.companyName == companyName &&
      other.companyPhone == companyPhone &&
      other.clientName == clientName &&
      other.visitDate == visitDate &&
      sameElements(other.zones, zones);

  @override
  int get hashCode => Object.hash(companyName, companyPhone, clientName, visitDate, Object.hashAll(zones));

  @override
  String toString() => 'ReportDocument($companyName, $companyPhone, $clientName, $visitDate, $zones)';
}

/// What a report prints for one zone: its name, its status, the two photo slots, and the note.
final class ReportZone {
  const new({
    required this.name,
    required this.beforePhoto,
    required this.afterPhoto,
    required this.note,
    this.beforePhotoSource = PhotoSource.unknown,
    this.afterPhotoSource = PhotoSource.unknown,
    this.beforeCapturedAt,
    this.afterCapturedAt,
    this.status = ZoneStatus.done,
    this.reason = '',
  });

  /// The zone of [record], with the note without the space around it, and the reason in the same form for an
  /// exception. A done zone has no reason, because every reader of a done record ignores the reason that it keeps.
  ///
  /// A line of the note and of the reason ends with a line feed alone, because a font has no glyph for a carriage
  /// return, which pasted text can hold.
  factory fromRecord(ZoneRecord record) => ReportZone(
    name: record.zoneName,
    beforePhoto: record.beforePhoto,
    afterPhoto: record.afterPhoto,
    beforePhotoSource: record.beforePhotoSource,
    afterPhotoSource: record.afterPhotoSource,
    beforeCapturedAt: record.beforeCapturedAt,
    afterCapturedAt: record.afterCapturedAt,
    note: _printable(record.note),
    status: record.status,
    reason: record.status == ZoneStatus.done ? '' : _printable(record.reason),
  );

  static String _printable(String text) => text.replaceAll(_carriageReturn, '\n').trim();

  /// A carriage return with the line feed after it, when it has one.
  static final _carriageReturn = RegExp(r'\r\n?');

  final String name;

  /// The photo before cleaning, or null for a slot that the report prints empty.
  final PhotoRef? beforePhoto;

  /// The photo after cleaning, or null for a slot that the report prints empty.
  final PhotoRef? afterPhoto;
  final PhotoSource beforePhotoSource;
  final PhotoSource afterPhotoSource;
  final DateTime? beforeCapturedAt;
  final DateTime? afterCapturedAt;

  /// The note, or an empty text when the zone has none. A report prints no note block for an empty text.
  final String note;

  /// Whether the visit cleaned the zone as agreed.
  final ZoneStatus status;

  /// What is left or why, for an exception, or an empty text.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is ReportZone &&
      other.name == name &&
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
    name,
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

  @override
  String toString() => 'ReportZone($name, ${beforePhoto?.path}, ${afterPhoto?.path}, $note, ${status.name}, $reason)';
}
