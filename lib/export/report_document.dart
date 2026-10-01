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
  final String clientName;
  final VisitDate visitDate;

  /// The zones that the report prints, in order.
  final List<ReportZone> zones;

  /// Every photo that the report prints, in the order of the zones, the before photo of a zone first.
  List<PhotoRef> get photos => [
    for (final zone in zones) ...[?zone.beforePhoto, ?zone.afterPhoto],
  ];

  @override
  bool operator ==(Object other) =>
      other is ReportDocument &&
      other.companyName == companyName &&
      other.clientName == clientName &&
      other.visitDate == visitDate &&
      sameElements(other.zones, zones);

  @override
  int get hashCode => Object.hash(companyName, clientName, visitDate, Object.hashAll(zones));

  @override
  String toString() => 'ReportDocument($companyName, $clientName, $visitDate, $zones)';
}

/// What a report prints for one zone: its name, the two photo slots, and the note.
final class ReportZone {
  const new({required this.name, required this.beforePhoto, required this.afterPhoto, required this.note});

  /// The zone of [record], with the note without the space around it.
  ///
  /// A line of the note ends with a line feed alone, because a font has no glyph for a carriage return, which pasted
  /// text can hold.
  factory fromRecord(ZoneRecord record) => ReportZone(
    name: record.zoneName,
    beforePhoto: record.beforePhoto,
    afterPhoto: record.afterPhoto,
    note: record.note.replaceAll(_carriageReturn, '\n').trim(),
  );

  /// A carriage return with the line feed after it, when it has one.
  static final _carriageReturn = RegExp(r'\r\n?');

  final String name;

  /// The photo before cleaning, or null for a slot that the report prints empty.
  final PhotoRef? beforePhoto;

  /// The photo after cleaning, or null for a slot that the report prints empty.
  final PhotoRef? afterPhoto;

  /// The note, or an empty text when the zone has none. A report prints no note block for an empty text.
  final String note;

  @override
  bool operator ==(Object other) =>
      other is ReportZone &&
      other.name == name &&
      other.beforePhoto == beforePhoto &&
      other.afterPhoto == afterPhoto &&
      other.note == note;

  @override
  int get hashCode => Object.hash(name, beforePhoto, afterPhoto, note);

  @override
  String toString() => 'ReportZone($name, ${beforePhoto?.path}, ${afterPhoto?.path}, $note)';
}
