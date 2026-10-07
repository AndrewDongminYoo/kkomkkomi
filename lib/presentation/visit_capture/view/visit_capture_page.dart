import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/shared/confirm_dialog.dart';
import 'package:kkomkkomi/presentation/shared/corner_radius.dart';
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';
import 'package:kkomkkomi/presentation/shared/load_failure.dart';
import 'package:kkomkkomi/presentation/shared/notice.dart';
import 'package:kkomkkomi/presentation/shared/photo_thumbnail.dart';
import 'package:kkomkkomi/presentation/shared/save_guard.dart';
import 'package:kkomkkomi/presentation/visit_capture/cubit/visit_capture_cubit.dart';
import 'package:kkomkkomi/presentation/visit_report/visit_report.dart';
import 'package:material_ui/material_ui.dart';

/// The width of a photo over its height, in a photo control and in a previous photo.
const double _photoAspectRatio = 4 / 3;

/// The space between the before column and the after column of a zone.
const _columnGap = 12.0;

/// The largest text scale of the title of the AppBar, which is the scale that the AppBar itself clamps its title to,
/// so that a large text size does not let the title take the screen.
const _maxTitleTextScale = 1.34;

/// The width of the back button before the title of the AppBar, which is the default leading width of the AppBar.
const double _backButtonWidth = kToolbarHeight;

/// The space above and below the title of the AppBar when the title is taller than the default toolbar.
const _titleVerticalPadding = 8.0;

/// The most lines of the client name in the title of the AppBar, the same as in the PDF of the report. A client name
/// has no length limit, so a longer name ends in an ellipsis and the list of zones keeps room on the screen.
const _clientNameMaxLines = 3;

/// The screen of one visit: for each zone record a before photo, an after photo, the previous photos, the status with
/// the reason of an exception, and a note.
class VisitCapturePage extends StatelessWidget {
  const new({required this.visitId, this.recovery, super.key});

  final String visitId;

  /// What the start of the app did with the photo of a capture of this visit whose answer the app lost, or null when
  /// the screen opens for another reason. The screen says it once, when the visit shows.
  final LostCaptureRecovery? recovery;

  static Route<void> route({required String visitId, LostCaptureRecovery? recovery}) => MaterialPageRoute<void>(
    builder: (_) => VisitCapturePage(visitId: visitId, recovery: recovery),
  );

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = VisitCaptureCubit(
          visitId: visitId,
          visits: context.read<VisitRepository>(),
          clients: context.read<ClientRepository>(),
          photoCapture: context.read<PhotoCapture>(),
          photoStore: context.read<PhotoStore>(),
          idGenerator: context.read<IdGenerator>(),
          openCaptures: context.read<OpenCaptureRepository>(),
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: VisitCaptureView(recovery: recovery),
    );
  }
}

class VisitCaptureView extends StatelessWidget {
  const new({this.recovery, super.key});

  /// What the start of the app did with a lost photo of this visit, which the view says when the visit shows.
  final LostCaptureRecovery? recovery;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocListener<VisitCaptureCubit, VisitCaptureState>(
      listenWhen: (previous, current) => recovery != null && previous.visit == null && current.visit != null,
      listener: (context, _) {
        final message = recovery!.isRecovered
            ? l10n.visitCaptureRecoveredPhotoMessage
            : l10n.visitCaptureRecoveryFailedMessage;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: KeepAllText(message)));
      },
      child: _buildScreen(context, l10n),
    );
  }

  Widget _buildScreen(BuildContext context, AppLocalizations l10n) {
    return BlocConsumer<VisitCaptureCubit, VisitCaptureState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        final message = switch (state.status) {
          VisitCaptureStatus.captureFailed => l10n.photoCaptureFailedMessage,
          VisitCaptureStatus.captureDenied => l10n.photoCaptureDeniedMessage,
          VisitCaptureStatus.saveFailed => l10n.saveFailedMessage,
          VisitCaptureStatus.loading ||
          VisitCaptureStatus.loadFailed ||
          VisitCaptureStatus.ready ||
          VisitCaptureStatus.capturing => null,
        };
        if (message == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: KeepAllText(message)));
      },
      builder: (context, state) {
        final visit = state.visit;
        // A person who leaves while a photo is on its way would not see that it was not saved.
        return SaveGuard(
          isSaving: state.status == VisitCaptureStatus.capturing,
          // A note is different: the person types on while it is on its way, so only the back press waits for the
          // answer. A person who then leaves with a note that storage did not take is asked first.
          child: PopScope(
            canPop: state.canLeave,
            onPopInvokedWithResult: (didPop, _) {
              final isAnswered = !state.isSavingNote && state.status != VisitCaptureStatus.capturing;
              if (!didPop && isAnswered && !state.isStored) unawaited(_confirmLeave(context));
            },
            child: Scaffold(
              appBar: _buildAppBar(context, state),
              body: SafeArea(
                child: switch (visit) {
                  null when state.status == VisitCaptureStatus.loadFailed => LoadFailure(
                    message: l10n.visitCaptureLoadFailedMessage,
                    onRetry: () => unawaited(context.read<VisitCaptureCubit>().load()),
                  ),
                  null => const Center(child: CircularProgressIndicator()),
                  Visit(:final zoneRecords) when zoneRecords.isEmpty => _EmptyVisit(l10n.visitCaptureEmptyMessage),
                  Visit(:final id, :final zoneRecords) => _ZoneList(state: state, visitId: id, records: zoneRecords),
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// The AppBar of the visit: the name of the client with the visit date under it, in the order of the report
  /// preview, or the date alone when storage did not give the client.
  ///
  /// A client name can be long, and the AppBar cuts a title that is taller than its toolbar, so the toolbar takes
  /// the height of the title at the width that the title has beside a back button. The name shows at most
  /// [_clientNameMaxLines] lines, so the toolbar never takes the screen.
  PreferredSizeWidget _buildAppBar(BuildContext context, VisitCaptureState state) {
    final visit = state.visit;
    if (visit == null) return AppBar();
    final date = context.l10n.visitDateLabel(
      DateTime(visit.visitDate.year, visit.visitDate.month, visit.visitDate.day),
    );
    final clientName = state.clientName;
    if (clientName == null) return AppBar(title: KeepAllText(date));

    final theme = Theme.of(context);
    final lines = [
      (clientName, theme.textTheme.titleMedium, _clientNameMaxLines),
      (date, theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), null),
    ];
    final textScaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _maxTitleTextScale);
    final width = math.max<double>(
      0,
      MediaQuery.sizeOf(context).width -
          MediaQuery.paddingOf(context).horizontal -
          _backButtonWidth -
          2 * NavigationToolbar.kMiddleSpacing,
    );
    // A Text widget applies these settings of the system to its style, so the measurement applies them too, and it
    // measures the string with the joiners that KeepAllText shows.
    final systemOverrides = TextStyle(
      fontWeight: MediaQuery.boldTextOf(context) ? FontWeight.bold : null,
      height: MediaQuery.maybeLineHeightScaleFactorOverrideOf(context),
      letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
      wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
    );
    var titleHeight = 0.0;
    for (final (text, style, maxLines) in lines) {
      final painter = TextPainter(
        text: TextSpan(text: keepAll(text), style: (style ?? const TextStyle()).merge(systemOverrides)),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '\u2026',
        locale: Localizations.maybeLocaleOf(context),
      )..layout(maxWidth: width);
      titleHeight += painter.height;
      painter.dispose();
    }

    return AppBar(
      toolbarHeight: math.max(kToolbarHeight, titleHeight + 2 * _titleVerticalPadding),
      title: MediaQuery.withClampedTextScaling(
        maxScaleFactor: _maxTitleTextScale,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The AppBar shows its title on one line with an ellipsis, which would cut a name that fits in a few lines.
            for (final (text, style, maxLines) in lines)
              KeepAllText(
                text,
                style: style,
                softWrap: true,
                maxLines: maxLines,
                overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  /// Asks before the person leaves with a note that storage did not take, and closes the screen on a yes.
  Future<void> _confirmLeave(BuildContext context) async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final leaves = await showConfirmDialog(
      context: context,
      title: l10n.visitLeaveUnsavedDialogTitle,
      message: l10n.visitLeaveUnsavedDialogMessage,
      confirmLabel: l10n.visitLeaveUnsavedConfirmButton,
      isDestructive: true,
    );
    if (leaves) navigator.pop();
  }
}

/// The zones of the visit in one list, under a notice while storage does not hold a note. The control that opens
/// the report ends the list.
class _ZoneList extends StatelessWidget {
  const new({required this.state, required this.visitId, required this.records});

  final VisitCaptureState state;
  final String visitId;
  final List<ZoneRecord> records;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The notice stays on the screen while the notes are not saved, because a message that leaves would let
          // the person type on without knowing.
          if (!state.isStored)
            ConstrainedBox(
              // At most half of the height, so that the zones stay in reach at a large text size.
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: const SingleChildScrollView(child: _UnsavedNotice()),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: records.length + 1,
              itemBuilder: (context, index) {
                if (index == records.length) return _ReportButton(visitId: visitId, isEnabled: state.canLeave);
                final record = records[index];
                return _ZoneCapture(
                  key: ValueKey(record.zoneId),
                  record: record,
                  previousPhotos: state.previousPhotos[record.zoneId],
                  pathOf: state.pathOf,
                  isCapturing: state.status == VisitCaptureStatus.capturing,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the report of the visit.
class _ReportButton extends StatelessWidget {
  const new({required this.visitId, required this.isEnabled});

  final String visitId;

  /// False while storage does not hold a note or a note is on its way to it, because the report reads the visit
  /// from storage and would lack a note that storage then does not take. The notice of unsaved notes says why.
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: FilledButton(
        onPressed: isEnabled
            ? () {
                // The note would take the focus again, and open the keyboard, when the person comes back.
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.of(context).push(VisitReportPage.route(visitId: visitId));
              }
            : null,
        child: KeepAllText(context.l10n.visitReportOpenButton),
      ),
    );
  }
}

/// Says that storage did not take a note, and offers to save again.
class _UnsavedNotice extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Notice(
          tone: NoticeTone.error,
          children: [
            KeepAllText(l10n.visitUnsavedMessage),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => unawaited(context.read<VisitCaptureCubit>().saveAgain()),
                child: KeepAllText(l10n.visitSaveAgainButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyVisit extends StatelessWidget {
  const new(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: KeepAllText(message, textAlign: TextAlign.center),
      ),
    );
  }
}

/// One zone of the visit: its name, the two photo controls, the previous photos, the status, the reason of an
/// exception, and the note.
class _ZoneCapture extends StatelessWidget {
  const new({
    required this.record,
    required this.previousPhotos,
    required this.pathOf,
    required this.isCapturing,
    super.key,
  });

  final ZoneRecord record;

  /// The photos of the newest earlier visit that recorded the zone, or null when no earlier visit recorded it.
  final PreviousPhotos? previousPhotos;

  /// Gives the absolute path of the file of a photo.
  final String Function(PhotoRef photo) pathOf;
  final bool isCapturing;

  @override
  Widget build(BuildContext context) {
    final previous = previousPhotos;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: KeepAllText(record.zoneName, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final slot in PhotoSlot.values) ...[
                if (slot != PhotoSlot.values.first) const SizedBox(width: _columnGap),
                Expanded(
                  child: _PhotoControl(zoneId: record.zoneId, slot: slot, photo: record.photoIn(slot), pathOf: pathOf),
                ),
              ],
            ],
          ),
          // An earlier record without a photo has nothing to show.
          if (previous != null && (previous.beforePhoto != null || previous.afterPhoto != null)) ...[
            const SizedBox(height: 12),
            _PreviousPhotoRow(previousPhotos: previous, pathOf: pathOf),
          ],
          const SizedBox(height: 12),
          _StatusChoice(zoneId: record.zoneId, status: record.status, isEnabled: !isCapturing),
          if (record.status != ZoneStatus.done) ...[
            const SizedBox(height: 12),
            _EntryField(
              // The record keeps its reason while its status is done, so the field shows it again at the next
              // exception.
              key: const ValueKey('reason'),
              label: record.status == ZoneStatus.partlyDone
                  ? context.l10n.zoneReasonPartlyDoneLabel
                  : context.l10n.zoneReasonNotDoneLabel,
              text: record.reason,
              emptyHelper: context.l10n.zoneReasonHelper,
              readOnly: isCapturing,
              onChanged: (reason) => unawaited(context.read<VisitCaptureCubit>().editReason(record.zoneId, reason)),
            ),
          ],
          const SizedBox(height: 12),
          _EntryField(
            key: const ValueKey('note'),
            label: context.l10n.noteFieldLabel,
            text: record.note,
            readOnly: isCapturing,
            onChanged: (note) => unawaited(context.read<VisitCaptureCubit>().editNote(record.zoneId, note)),
          ),
        ],
      ),
    );
  }
}

/// The control that takes the photo of one slot. It shows the photo when the slot holds one, and takes it again.
class _PhotoControl extends StatelessWidget {
  const new({required this.zoneId, required this.slot, required this.photo, required this.pathOf});

  final String zoneId;
  final PhotoSlot slot;
  final PhotoRef? photo;
  final String Function(PhotoRef photo) pathOf;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final photo = this.photo;
    final label = switch ((slot, photo == null)) {
      (PhotoSlot.before, true) => l10n.photoTakeBeforeButton,
      (PhotoSlot.before, false) => l10n.photoRetakeBeforeButton,
      (PhotoSlot.after, true) => l10n.photoTakeAfterButton,
      (PhotoSlot.after, false) => l10n.photoRetakeAfterButton,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cornerRadius)),
          ),
          clipBehavior: Clip.antiAlias,
          onPressed: () {
            // The keyboard would cover the screen when the camera closes, and the note takes no text during a capture.
            FocusManager.instance.primaryFocus?.unfocus();
            unawaited(context.read<VisitCaptureCubit>().capturePhoto(zoneId, slot));
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: _photoAspectRatio,
                child: photo == null
                    ? ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Center(child: Icon(Icons.photo_camera_outlined, size: 32)),
                      )
                    : PhotoThumbnail(path: pathOf(photo)),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: KeepAllText(label, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            unawaited(context.read<VisitCaptureCubit>().capturePhoto(zoneId, slot, source: PhotoSource.gallery));
          },
          child: KeepAllText(slot == PhotoSlot.before ? l10n.photoGalleryBeforeButton : l10n.photoGalleryAfterButton),
        ),
      ],
    );
  }
}

/// The photos that an earlier visit took for the zone, each under the control of its slot.
class _PreviousPhotoRow extends StatelessWidget {
  const new({required this.previousPhotos, required this.pathOf});

  final PreviousPhotos previousPhotos;
  final String Function(PhotoRef photo) pathOf;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final date = previousPhotos.visitDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeepAllText(
          l10n.previousPhotosTitle(DateTime(date.year, date.month, date.day)),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PreviousPhoto(
                photo: previousPhotos.beforePhoto,
                label: l10n.previousBeforePhotoLabel,
                pathOf: pathOf,
              ),
            ),
            const SizedBox(width: _columnGap),
            Expanded(
              child: _PreviousPhoto(
                photo: previousPhotos.afterPhoto,
                label: l10n.previousAfterPhotoLabel,
                pathOf: pathOf,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviousPhoto extends StatelessWidget {
  const new({required this.photo, required this.label, required this.pathOf});

  final PhotoRef? photo;

  /// What a screen reader says for the photo.
  final String label;
  final String Function(PhotoRef photo) pathOf;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    if (photo == null) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        width: 96,
        child: AspectRatio(
          aspectRatio: _photoAspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: PhotoThumbnail(path: pathOf(photo), semanticLabel: label),
          ),
        ),
      ),
    );
  }
}

/// The status of one zone: a chip for each status, which a press sets. The chips go to the next line when they do not
/// fit, so that a narrow screen with a large text size cuts none.
class _StatusChoice extends StatelessWidget {
  const new({required this.zoneId, required this.status, required this.isEnabled});

  final String zoneId;
  final ZoneStatus status;

  /// False while a capture runs, because the visit then takes no change.
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeepAllText(l10n.zoneStatusLabel, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in ZoneStatus.values)
              ChoiceChip(
                label: KeepAllText(switch (option) {
                  ZoneStatus.done => l10n.zoneStatusDoneLabel,
                  ZoneStatus.partlyDone => l10n.reportPartlyDoneLabel,
                  ZoneStatus.notDone => l10n.reportNotDoneLabel,
                }),
                selected: option == status,
                onSelected: isEnabled
                    ? (_) => unawaited(context.read<VisitCaptureCubit>().setStatus(zoneId, option))
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// A text of one zone, such as its note or its reason. Each edit goes to the cubit, which saves it at once.
///
/// The label is a text of its own above the field, as in `NameField`, so that a large text size cuts nothing.
class _EntryField extends StatefulWidget {
  const new({
    required this.label,
    required this.text,
    required this.readOnly,
    required this.onChanged,
    this.emptyHelper,
    super.key,
  });

  final String label;

  /// The text that the field holds when it opens. A later value does not replace what the person typed.
  final String text;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  /// The text under the field while the field is empty, or null for none.
  final String? emptyHelper;

  @override
  State<_EntryField> createState() => _EntryFieldState();
}

class _EntryFieldState extends State<_EntryField> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final emptyHelper = widget.emptyHelper;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeepAllText(widget.label, style: Theme.of(context).textTheme.labelLarge),
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, value, _) => TextField(
              controller: _controller,
              readOnly: widget.readOnly,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: null,
              decoration: InputDecoration(
                helper: emptyHelper != null && value.text.isEmpty ? KeepAllText(emptyHelper) : null,
              ),
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
