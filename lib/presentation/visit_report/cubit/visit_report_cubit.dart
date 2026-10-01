import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/export/export.dart';

part 'visit_report_state.dart';

/// Loads the report of one visit, and shares it as a PDF.
class VisitReportCubit extends Cubit<VisitReportState> {
  new({
    required this._visitId,
    required this._visits,
    required this._clients,
    required this._companyProfile,
    required this._photoStore,
    required this._reportFont,
    required this._reportShare,
  }) : super(const VisitReportState());

  final String _visitId;
  final VisitRepository _visits;
  final ClientRepository _clients;
  final CompanyProfileRepository _companyProfile;
  final PhotoStore _photoStore;
  final ReportFont _reportFont;
  final ReportShare _reportShare;

  /// Reads the visit, its client, and the company profile, and builds the report from them.
  ///
  /// A visit or a client that storage does not have is a failed load, because neither is ever deleted. A call does
  /// nothing while a share is on its way, and after the screen closed.
  Future<void> load() async {
    if (isClosed || state.status == VisitReportStatus.sharing) return;
    if (state.status != VisitReportStatus.loading) emit(const VisitReportState());
    try {
      final visit = await _visits.visitById(_visitId);
      final client = visit == null ? null : await _clients.clientById(visit.clientId);
      if (visit == null || client == null) {
        _show(const VisitReportState(status: VisitReportStatus.loadFailed));
        return;
      }
      final companyProfile = await _companyProfile.load();
      final photoDirectory = await _photoStore.directoryPath();
      _show(
        VisitReportState(
          status: VisitReportStatus.ready,
          document: ReportDocument.fromVisit(visit: visit, client: client, companyProfile: companyProfile),
          zonesLackingPhoto: [
            for (final record in visit.zoneRecords)
              if (record.emptySlots.isNotEmpty) record,
          ],
          photoDirectory: photoDirectory,
        ),
      );
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
      _show(const VisitReportState(status: VisitReportStatus.loadFailed));
    }
  }

  /// Renders the report as a PDF with the texts of [labels], and opens the share sheet with the file.
  ///
  /// The status is [VisitReportStatus.sharing] until the share sheet is open, and [VisitReportStatus.shareFailed]
  /// when a photo file, the font, the renderer, or the share sheet failed. A call does nothing while the state
  /// cannot share: see [VisitReportState.canShare].
  Future<void> share(ReportLabels labels) async {
    final document = state.document;
    if (document == null || !state.canShare) return;
    emit(state.copyWith(status: VisitReportStatus.sharing));
    try {
      final photos = <PhotoRef, Uint8List>{};
      for (final photo in document.photos) {
        photos[photo] = await _photoStore.read(photo);
      }
      final bytes = await renderReportPdf(document, labels: labels, font: await _reportFont.load(), photos: photos);
      await _reportShare.sharePdf(
        bytes: bytes,
        fileName: reportFileName(
          title: labels.title,
          clientName: document.clientName,
          visitDate: document.visitDate,
        ),
      );
      _show(state.copyWith(status: VisitReportStatus.ready));
    } on Object catch (error, stackTrace) {
      // The image decoder fails with an `Error` for a file that is no image, and a missing file fails with an
      // `Exception`. Both must end the share, because the screen takes no touch while a share is on its way, so
      // the clause catches every object.
      _report(error, stackTrace);
      _show(state.copyWith(status: VisitReportStatus.shareFailed));
    }
  }

  void _show(VisitReportState next) {
    if (!isClosed) emit(next);
  }

  void _report(Object error, StackTrace stackTrace) {
    if (!isClosed) addError(error, stackTrace);
  }
}
