// Every field of the class is final, and `package:meta`, which has `@immutable`, is not a dependency.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

part of 'visit_report_cubit.dart';

enum VisitReportStatus {
  /// The report is on its way from storage.
  loading,

  /// Storage did not give what the report needs.
  loadFailed,

  /// The state holds the report, and the last share opened the share sheet or no share ran.
  ready,

  /// The PDF is on its way to the share sheet. The screen takes no touch.
  sharing,

  /// The share sheet did not open with the PDF.
  shareFailed,
}

final class VisitReportState {
  const new({
    this.status = VisitReportStatus.loading,
    this.document,
    this.zonesLackingPhoto = const [],
    this.photoDirectory = '',
  });

  final VisitReportStatus status;

  /// The report of the visit, or null while it is not loaded.
  final ReportDocument? document;

  /// The zone records of the visit that lack the before photo, the after photo, or both, in the order of the visit.
  ///
  /// A record without a photo and without a note is in this list and not in [document].
  final List<ZoneRecord> zonesLackingPhoto;

  /// The absolute path of the directory that the path of each photo is relative to, in this launch of the app.
  final String photoDirectory;

  /// Whether a share can start: the report is loaded, it prints a zone, and no share is on its way.
  bool get canShare =>
      (status == VisitReportStatus.ready || status == VisitReportStatus.shareFailed) &&
      (document?.zones.isNotEmpty ?? false);

  /// The absolute path of the file of [photo] in this launch of the app.
  String pathOf(PhotoRef photo) => '$photoDirectory/${photo.path}';

  VisitReportState copyWith({VisitReportStatus? status}) => VisitReportState(
    status: status ?? this.status,
    document: document,
    zonesLackingPhoto: zonesLackingPhoto,
    photoDirectory: photoDirectory,
  );

  @override
  bool operator ==(Object other) =>
      other is VisitReportState &&
      other.status == status &&
      other.document == document &&
      other.photoDirectory == photoDirectory &&
      sameElements(other.zonesLackingPhoto, zonesLackingPhoto);

  @override
  int get hashCode => Object.hash(status, document, photoDirectory, Object.hashAll(zonesLackingPhoto));
}
