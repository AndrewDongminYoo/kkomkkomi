import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/export/export.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/company_profile/company_profile.dart';
import 'package:kkomkkomi/presentation/shared/confirm_dialog.dart';
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';
import 'package:kkomkkomi/presentation/shared/load_failure.dart';
import 'package:kkomkkomi/presentation/shared/notice.dart';
import 'package:kkomkkomi/presentation/shared/photo_thumbnail.dart';
import 'package:kkomkkomi/presentation/shared/save_guard.dart';
import 'package:kkomkkomi/presentation/visit_report/cubit/report_link_cubit.dart';
import 'package:kkomkkomi/presentation/visit_report/cubit/visit_report_cubit.dart';
import 'package:material_ui/material_ui.dart';

/// The texts of the report of a visit on [visitDate], in the language of [l10n].
ReportLabels reportLabelsOf(AppLocalizations l10n, VisitDate visitDate) => ReportLabels(
  title: l10n.reportDocumentTitle,
  clientHeading: l10n.reportClientHeading,
  visitDateHeading: l10n.reportVisitDateHeading,
  visitDate: l10n.visitDateLabel(DateTime(visitDate.year, visitDate.month, visitDate.day)),
  beforePhoto: l10n.reportBeforePhotoLabel,
  afterPhoto: l10n.reportAfterPhotoLabel,
  notPhotographed: l10n.reportNotPhotographedLabel,
  partlyDone: l10n.reportPartlyDoneLabel,
  notDone: l10n.reportNotDoneLabel,
  summaryOf: (done, total) => l10n.reportSummary(done, total),
  note: l10n.reportNoteLabel,
  footer: l10n.reportFooter,
);

/// The screen of the report of one visit: what the report lacks, a preview, and the controls that share the link
/// and the PDF.
class VisitReportPage extends StatelessWidget {
  const new({required this.visitId, super.key});

  final String visitId;

  static Route<void> route({required String visitId}) =>
      MaterialPageRoute<void>(builder: (_) => VisitReportPage(visitId: visitId));

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) {
            final cubit = VisitReportCubit(
              visitId: visitId,
              visits: context.read<VisitRepository>(),
              clients: context.read<ClientRepository>(),
              companyProfile: context.read<CompanyProfileRepository>(),
              photoStore: context.read<PhotoStore>(),
              reportFont: context.read<ReportFont>(),
              reportShare: context.read<ReportShare>(),
              identity: context.read<Identity>(),
            );
            unawaited(cubit.load());
            return cubit;
          },
        ),
        BlocProvider(
          create: (context) {
            final cubit = ReportLinkCubit(
              visitId: visitId,
              visits: context.read<VisitRepository>(),
              publishQueue: context.read<PublishQueue>(),
              linkShare: context.read<LinkShare>(),
            );
            unawaited(cubit.load());
            return cubit;
          },
        ),
      ],
      child: const VisitReportView(),
    );
  }
}

class VisitReportView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    void showShareFailed() => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: KeepAllText(l10n.reportShareFailedMessage)));
    return MultiBlocListener(
      listeners: [
        BlocListener<VisitReportCubit, VisitReportState>(
          listenWhen: (previous, current) =>
              previous.status != current.status && current.status == VisitReportStatus.shareFailed,
          listener: (_, _) => showShareFailed(),
        ),
        BlocListener<ReportLinkCubit, ReportLinkState>(
          listenWhen: (previous, current) =>
              previous.status != current.status && current.status == ReportLinkStatus.shareFailed,
          listener: (_, _) => showShareFailed(),
        ),
      ],
      child: const _ReportScaffold(),
    );
  }
}

/// The scaffold of the report screen, under the listeners that show the share failures.
class _ReportScaffold extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final linkState = context.watch<ReportLinkCubit>().state;
    return BlocBuilder<VisitReportCubit, VisitReportState>(
      builder: (context, state) {
        final document = state.document;
        // A person who leaves while the PDF is on its way would get a share sheet over another screen.
        return SaveGuard(
          isSaving: state.status == VisitReportStatus.sharing,
          child: Scaffold(
            appBar: AppBar(title: KeepAllText(l10n.visitReportTitle)),
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
                    linkState: linkState,
                    // The link shares the same zones as the PDF, so it waits for a report that prints a zone too.
                    onShareLink: linkState.canShare && document.zones.isNotEmpty
                        ? () => unawaited(_shareLink(context, linkState))
                        : null,
                  ),
          ),
        );
      },
    );
  }

  /// Starts the link share. Before the first link of the client, the person learns that anyone with the link can
  /// open the reports, and the share starts only when they go on.
  static Future<void> _shareLink(BuildContext context, ReportLinkState linkState) async {
    final cubit = context.read<ReportLinkCubit>();
    final report = context.read<VisitReportCubit>();
    // The upload can end after the person opened another screen or started the share of the PDF. The share sheet of
    // the link then waits for the next press, so that it never opens over another screen or another share sheet.
    bool mayOpenShareSheet() =>
        context.mounted &&
        (ModalRoute.of(context)?.isCurrent ?? false) &&
        report.state.status != VisitReportStatus.sharing;
    if (linkState.isFirstShare) {
      final l10n = context.l10n;
      final goOn = await showConfirmDialog(
        context: context,
        title: l10n.reportLinkNoticeTitle,
        message: l10n.reportLinkNoticeMessage,
        confirmLabel: l10n.reportLinkNoticeConfirmButton,
      );
      if (!goOn) return;
    }
    await cubit.share(mayOpenShareSheet: mayOpenShareSheet);
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
          child: KeepAllText(l10n.reportPreviewTitle, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        _ReportPreview(document: document, pathOf: state.pathOf, showsFooterText: state.showsFooterText),
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
    return Notice(
      children: [
        KeepAllText(l10n.reportCompanyNameMissingMessage),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () => unawaited(_openCompanyProfile(context)),
            child: KeepAllText(l10n.reportCompanyNameAddButton),
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
    return Notice(
      children: [
        Semantics(
          header: true,
          child: KeepAllText(l10n.reportMissingPhotosTitle, style: Theme.of(context).textTheme.titleSmall),
        ),
        const SizedBox(height: 4),
        KeepAllText(l10n.reportMissingPhotosMessage),
        const SizedBox(height: 8),
        for (final record in records)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: KeepAllText(_gapOf(record, l10n)),
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

/// The report as the PDF prints it: the same texts and the same zones, in the layout of the screen.
class _ReportPreview extends StatelessWidget {
  const new({required this.document, required this.pathOf, required this.showsFooterText});

  final ReportDocument document;

  /// Gives the absolute path of the file of a photo.
  final String Function(PhotoRef photo) pathOf;

  /// Whether the preview shows the footer text, as the PDF prints it.
  final bool showsFooterText;

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
            if (document.companyName case final companyName?) KeepAllText(companyName, style: secondary),
            if (document.companyPhone.isNotEmpty) KeepAllText(document.companyPhone, style: secondary),
            KeepAllText(labels.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            KeepAllText(document.clientName, style: theme.textTheme.titleMedium),
            KeepAllText(labels.visitDate, style: secondary),
            if (document.zones.isNotEmpty) ...[
              const SizedBox(height: 8),
              KeepAllText(
                labels.summaryOf(document.doneCount, document.zones.length),
                style: theme.textTheme.titleSmall,
              ),
              for (final zone in document.exceptions)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: KeepAllText(labels.exceptionLineOf(zone)),
                ),
            ],
            const Divider(height: 24),
            if (document.zones.isEmpty) KeepAllText(l10n.reportEmptyMessage),
            for (final zone in document.zones) ...[
              _PreviewZone(zone: zone, labels: labels, pathOf: pathOf),
              const SizedBox(height: 16),
            ],
            if (showsFooterText) KeepAllText(labels.footer, style: secondary),
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: KeepAllText(zone.name, style: theme.textTheme.titleMedium),
              ),
            ),
            if (zone.status != ZoneStatus.done) ...[
              const SizedBox(width: 8),
              _StatusBadge(status: labels.statusOf(zone.status)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PreviewSlot(
                label: labels.beforePhoto,
                photo: zone.beforePhoto,
                emptyText: labels.emptySlotOf(zone.status),
                pathOf: pathOf,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PreviewSlot(
                label: labels.afterPhoto,
                photo: zone.afterPhoto,
                emptyText: labels.emptySlotOf(zone.status),
                pathOf: pathOf,
              ),
            ),
          ],
        ),
        if (zone.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeepAllText(labels.note, style: secondary),
                KeepAllText(zone.note),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The status of a zone that is not done, as a text inside an edge, as the PDF prints it.
class _StatusBadge extends StatelessWidget {
  const new({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.onSurface),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: KeepAllText(status, style: theme.textTheme.labelMedium),
      ),
    );
  }
}

/// One photo slot of the preview: [label] over the photo, or over an empty box for a photo that the zone lacks.
class _PreviewSlot extends StatelessWidget {
  const new({required this.label, required this.photo, required this.emptyText, required this.pathOf});

  final String label;
  final PhotoRef? photo;

  /// What the PDF prints in the slot when it holds no photo, which a screen reader reads for the empty slot.
  final String emptyText;
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
          KeepAllText(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          AspectRatio(
            aspectRatio: reportSlotAspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: photo == null
                  ? ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      // The PDF prints the text of the label here. An icon keeps its size at a large text size.
                      child: Center(child: Icon(Icons.no_photography_outlined, semanticLabel: emptyText)),
                    )
                  // A photo sits on white inside an edge, as in the PDF, so that the space beside it never looks like
                  // a slot without a photo.
                  : ColoredBox(
                      color: theme.colorScheme.surfaceContainerLowest,
                      // The edge is painted over the photo, which reaches two sides of the square slot and would
                      // hide the edge there.
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        // The whole photo shows, as in the PDF, so that the person sees every part that the share
                        // sends.
                        child: Semantics(
                          image: true,
                          child: PhotoThumbnail(path: pathOf(photo), fit: BoxFit.contain),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The controls that share the link and the PDF. They stay at the foot of the screen, under the preview.
///
/// The link is the main way to send a report, so its control comes first. A flavor without a backend shows the PDF
/// control alone.
class _ShareBar extends StatelessWidget {
  const new({required this.isSharing, required this.onShare, required this.linkState, required this.onShareLink});

  final bool isSharing;

  /// Starts the share of the PDF, or null while the report cannot be shared.
  final VoidCallback? onShare;

  final ReportLinkState linkState;

  /// Starts the share of the link, or null while it cannot start.
  final VoidCallback? onShareLink;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasLink = linkState.status != ReportLinkStatus.unavailable;
    final pdfLabel = isSharing ? _Progress(label: l10n.reportShareButton) : KeepAllText(l10n.reportShareButton);
    final message = _linkMessageOf(linkState, l10n);
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      // At a large text size the message and the two controls can be taller than the screen allows a bar, so the bar
      // takes at most half of the screen and scrolls. It starts at its end, where the controls are.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height / 2),
        child: SingleChildScrollView(
          reverse: true,
          // A bar at the foot of a scaffold gets loose constraints, and the buttons fill the width.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message case (final text, final tone)) ...[
                Semantics(
                  liveRegion: true,
                  child: Notice(tone: tone, children: [KeepAllText(text)]),
                ),
                const SizedBox(height: 8),
              ],
              if (hasLink) ...[
                FilledButton(
                  onPressed: onShareLink,
                  child: linkState.status == ReportLinkStatus.publishing
                      ? _Progress(label: l10n.reportLinkShareButton)
                      : KeepAllText(l10n.reportLinkShareButton),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: onShare, child: pdfLabel),
              ] else
                FilledButton(onPressed: onShare, child: pdfLabel),
            ],
          ),
        ),
      ),
    );
  }

  /// What the screen says about the link share in [state] and in which tone, or null when it says nothing.
  ///
  /// A job that waits for its next try is still on its way, so only a job that stopped is a failure.
  static (String, NoticeTone)? _linkMessageOf(ReportLinkState state, AppLocalizations l10n) => switch (state.status) {
    ReportLinkStatus.publishing => (l10n.reportLinkPublishingMessage, NoticeTone.info),
    ReportLinkStatus.waitingForRetry => (l10n.reportLinkWaitingMessage, NoticeTone.info),
    ReportLinkStatus.failed => (
      switch (state.failure) {
        PublishFailure.revoked => l10n.reportLinkRevokedMessage,
        PublishFailure.deletion => l10n.reportLinkStoppedByDeletionMessage,
        PublishFailure.photoMissing => l10n.reportLinkPhotoMissingMessage,
        PublishFailure.photoNotJpeg || PublishFailure.photoTooLarge => l10n.reportLinkPhotoUnusableMessage,
        PublishFailure.unavailable || PublishFailure.refused || null => l10n.reportLinkFailedMessage,
      },
      NoticeTone.error,
    ),
    ReportLinkStatus.published => (l10n.reportLinkPublishedMessage, NoticeTone.info),
    ReportLinkStatus.loading ||
    ReportLinkStatus.unavailable ||
    ReportLinkStatus.ready ||
    ReportLinkStatus.shareFailed => null,
  };
}

/// What a share control shows in place of its text while its share is on its way. A screen reader still reads
/// [label] as the name of the control.
class _Progress extends StatelessWidget {
  const new({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: label),
    );
  }
}
