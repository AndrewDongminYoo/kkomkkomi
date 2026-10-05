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
    required this._identity,
  }) : super(const VisitReportState());

  final String _visitId;
  final VisitRepository _visits;
  final ClientRepository _clients;
  final CompanyProfileRepository _companyProfile;
  final PhotoStore _photoStore;
  final ReportFont _reportFont;
  final ReportShare _reportShare;
  final Identity _identity;

  /// The check of a paid entitlement, which the first load starts, so that the screen asks once.
  Future<void>? _paidCheck;

  /// Whether the token of the user holds a paid entitlement, or null while the check has not answered.
  bool? _paid;

  /// Reads the visit, its client, and the company profile, and builds the report from them.
  ///
  /// The report shows without the footer text when `Identity.hasPaidEntitlement` answers true, the same token claim
  /// that decides the footer of the web report. The check asks Firebase for a newly issued token, which can take long
  /// without a network, so the report does not wait for it: it shows with the footer text until the check answers
  /// true, and a PDF that is shared before then prints the footer text.
  /// A visit or a client that storage does not have is a failed load, because neither is ever deleted. A call does
  /// nothing while a share is on its way, and after the screen closed.
  Future<void> load() async {
    if (isClosed || state.status == VisitReportStatus.sharing) return;
    if (state.status != VisitReportStatus.loading) emit(const VisitReportState());
    _paidCheck ??= _checkPaid();
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
          showsFooterText: _paid != true,
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
        // The PDF holds the JPEG file as it is, so a photo that the store kept before it removed the location gets
        // it removed here (issue 20).
        photos[photo] = withoutLocation(await _photoStore.read(photo));
      }
      final bytes = await renderReportPdf(
        document,
        labels: labels,
        font: await _reportFont.load(),
        photos: photos,
        showsFooterText: state.showsFooterText,
      );
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
      // A missing file, a file that is no well-formed JPEG, and a JPEG that the renderer cannot read fail with an
      // `Exception`. The renderer also holds code that throws objects that are none, such as the `String` of
      // `PdfJpegInfo` in `pdf` 3.13.1. Each must end the share, because the screen takes no touch while a share is on
      // its way, so the clause catches every object.
      _report(error, stackTrace);
      _show(state.copyWith(status: VisitReportStatus.shareFailed));
    }
  }

  /// Asks once whether the user holds a paid entitlement, and leaves the footer text out of a shown report when the
  /// answer is true. The call of the port never throws.
  Future<void> _checkPaid() async {
    final paid = _paid = await _identity.hasPaidEntitlement();
    if (paid && !isClosed && state.document != null) emit(state.copyWith(showsFooterText: false));
  }

  void _show(VisitReportState next) {
    if (!isClosed) emit(next);
  }

  void _report(Object error, StackTrace stackTrace) {
    if (!isClosed) addError(error, stackTrace);
  }
}
