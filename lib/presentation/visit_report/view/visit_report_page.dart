import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/export/export.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/company_profile/company_profile.dart';
import 'package:kkomkkomi/presentation/shared/load_failure.dart';
import 'package:kkomkkomi/presentation/shared/photo_thumbnail.dart';
import 'package:kkomkkomi/presentation/shared/save_guard.dart';
import 'package:kkomkkomi/presentation/visit_report/cubit/visit_report_cubit.dart';
import 'package:material_ui/material_ui.dart';

/// The texts of the report of a visit on [visitDate], in the language of [l10n].
ReportLabels reportLabelsOf(AppLocalizations l10n, VisitDate visitDate) => ReportLabels(
  title: l10n.reportDocumentTitle,
  visitDate: l10n.visitDateLabel(DateTime(visitDate.year, visitDate.month, visitDate.day)),
  beforePhoto: l10n.reportBeforePhotoLabel,
  afterPhoto: l10n.reportAfterPhotoLabel,
  noPhoto: l10n.reportNoPhotoLabel,
  note: l10n.reportNoteLabel,
  footer: l10n.reportFooter,
);

/// The screen of the report of one visit: what the report lacks, a preview, and the control that shares the PDF.
class VisitReportPage extends StatelessWidget {
  const new({required this.visitId, super.key});

  final String visitId;

  static Route<void> route({required String visitId}) =>
      MaterialPageRoute<void>(builder: (_) => VisitReportPage(visitId: visitId));

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = VisitReportCubit(
          visitId: visitId,
          visits: context.read<VisitRepository>(),
          clients: context.read<ClientRepository>(),
          companyProfile: context.read<CompanyProfileRepository>(),
          photoStore: context.read<PhotoStore>(),
          reportFont: context.read<ReportFont>(),
          reportShare: context.read<ReportShare>(),
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: const VisitReportView(),
    );
  }
}

class VisitReportView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<VisitReportCubit, VisitReportState>(
      listenWhen: (previous, current) =>
          previous.status != current.status && current.status == VisitReportStatus.shareFailed,
      listener: (context, _) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.reportShareFailedMessage))),
      builder: (context, state) {
        final document = state.document;
        // A person who leaves while the PDF is on its way would get a share sheet over another screen.
        return SaveGuard(
          isSaving: state.status == VisitReportStatus.sharing,
          child: Scaffold(
            appBar: AppBar(title: Text(l10n.visitReportTitle)),
            body: SafeArea(
              child: switch (document) {
                null when state.status == VisitReportStatus.loadFailed => LoadFailure(
                  message: l10n.visitReportLoadFailedMessage,
                  onRetry: () => unawaited(context.read<VisitReportCubit>().load()),
                ),
                null => const Center(child: CircularProgressIndicator()),
                _ => _ReportBody(state: state, document: document),
              },
            ),
            bottomNavigationBar: document == null
                ? null
                : _ShareBar(
                    isSharing: state.status == VisitReportStatus.sharing,
                    onShare: state.canShare
                        ? () => unawaited(
                            context.read<VisitReportCubit>().share(reportLabelsOf(l10n, document.visitDate)),
                          )
                        : null,
                  ),
          ),
        );
      },
    );
  }
}

/// What the report lacks, and under it the preview.
class _ReportBody extends StatelessWidget {
  const new({required this.state, required this.document});

  final VisitReportState state;
  final ReportDocument document;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (document.companyName == null) ...[
          const _CompanyNameNotice(),
          const SizedBox(height: 16),
        ],
        if (state.zonesLackingPhoto.isNotEmpty) ...[
          _MissingPhotos(records: state.zonesLackingPhoto),
          const SizedBox(height: 16),
        ],
        Semantics(
          header: true,
          child: Text(l10n.reportPreviewTitle, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        _ReportPreview(document: document, pathOf: state.pathOf),
      ],
    );
  }
}

/// Says that the report has no company name, and opens the company profile. The share does not wait for the name.
class _CompanyNameNotice extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Notice(
      children: [
        Text(l10n.reportCompanyNameMissingMessage),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () => unawaited(_openCompanyProfile(context)),
            child: Text(l10n.reportCompanyNameAddButton),
          ),
        ),
      ],
    );
  }

  /// Opens the company profile, and reads the report again when the person comes back, for a name that they saved.
  Future<void> _openCompanyProfile(BuildContext context) async {
    final cubit = context.read<VisitReportCubit>();
    await Navigator.of(context).push(CompanyProfilePage.route());
    await cubit.load();
  }
}

/// The zones that lack a photo, each with what it lacks.
class _MissingPhotos extends StatelessWidget {
  const new({required this.records});

  final List<ZoneRecord> records;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Notice(
      children: [
        Semantics(
          header: true,
          child: Text(l10n.reportMissingPhotosTitle, style: Theme.of(context).textTheme.titleSmall),
        ),
        const SizedBox(height: 4),
        Text(l10n.reportMissingPhotosMessage),
        const SizedBox(height: 8),
        for (final record in records)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_gapOf(record, l10n)),
          ),
      ],
    );
  }

  /// What [record], which lacks a photo, lacks.
  static String _gapOf(ZoneRecord record, AppLocalizations l10n) {
    if (!record.hasContent) return l10n.reportZoneLeftOut(record.zoneName);
    return switch (record.emptySlots) {
      [PhotoSlot.before] => l10n.reportMissingBeforePhoto(record.zoneName),
      [PhotoSlot.after] => l10n.reportMissingAfterPhoto(record.zoneName),
      _ => l10n.reportMissingBothPhotos(record.zoneName),
    };
  }
}

/// A box that sets a notice apart from the preview.
class _Notice extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}

/// The report as the PDF prints it: the same texts and the same zones, in the layout of the screen.
class _ReportPreview extends StatelessWidget {
  const new({required this.document, required this.pathOf});

  final ReportDocument document;

  /// Gives the absolute path of the file of a photo.
  final String Function(PhotoRef photo) pathOf;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final labels = reportLabelsOf(l10n, document.visitDate);
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (document.companyName case final companyName?) Text(companyName, style: secondary),
            Text(labels.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(document.clientName, style: theme.textTheme.titleMedium),
            Text(labels.visitDate, style: secondary),
            const Divider(height: 24),
            if (document.zones.isEmpty) Text(l10n.reportEmptyMessage),
            for (final zone in document.zones) ...[
              _PreviewZone(zone: zone, labels: labels, pathOf: pathOf),
              const SizedBox(height: 16),
            ],
            Text(labels.footer, style: secondary),
          ],
        ),
      ),
    );
  }
}

/// One zone of the preview: its name, the two photo slots, and the note.
class _PreviewZone extends StatelessWidget {
  const new({required this.zone, required this.labels, required this.pathOf});

  final ReportZone zone;
  final ReportLabels labels;
  final String Function(PhotoRef photo) pathOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(zone.name, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PreviewSlot(label: labels.beforePhoto, photo: zone.beforePhoto, labels: labels, pathOf: pathOf),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PreviewSlot(label: labels.afterPhoto, photo: zone.afterPhoto, labels: labels, pathOf: pathOf),
            ),
          ],
        ),
        if (zone.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(labels.note, style: secondary),
                Text(zone.note),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One photo slot of the preview: [label] over the photo, or over an empty box for a photo that the zone lacks.
class _PreviewSlot extends StatelessWidget {
  const new({required this.label, required this.photo, required this.labels, required this.pathOf});

  final String label;
  final PhotoRef? photo;
  final ReportLabels labels;
  final String Function(PhotoRef photo) pathOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = this.photo;
    // The label and the slot are one node for a screen reader, which then reads the label as the name of the photo,
    // or the label and that the slot holds no photo.
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          AspectRatio(
            aspectRatio: reportSlotAspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: photo == null
                    // The PDF prints the text of the label here. An icon keeps its size at a large text size.
                    ? Center(child: Icon(Icons.no_photography_outlined, semanticLabel: labels.noPhoto))
                    // The whole photo shows, as in the PDF, so that the person sees every part that the share sends.
                    : Semantics(
                        image: true,
                        child: PhotoThumbnail(path: pathOf(photo), fit: BoxFit.contain),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The control that shares the PDF. It stays at the foot of the screen, under the preview.
class _ShareBar extends StatelessWidget {
  const new({required this.isSharing, required this.onShare});

  final bool isSharing;

  /// Starts the share, or null while the report cannot be shared.
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      // A bar at the foot of a scaffold gets loose constraints, and the button fills the width.
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onShare,
          child: isSharing
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.l10n.reportShareButton),
        ),
      ),
    );
  }
}
