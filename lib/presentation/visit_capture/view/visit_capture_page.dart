import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/shared/confirm_dialog.dart';
import 'package:kkomkkomi/presentation/shared/load_failure.dart';
import 'package:kkomkkomi/presentation/shared/photo_thumbnail.dart';
import 'package:kkomkkomi/presentation/shared/save_guard.dart';
import 'package:kkomkkomi/presentation/visit_capture/cubit/visit_capture_cubit.dart';
import 'package:kkomkkomi/presentation/visit_report/visit_report.dart';
import 'package:material_ui/material_ui.dart';

/// The width of a photo over its height, in a photo control and in a previous photo.
const double _photoAspectRatio = 4 / 3;

/// The space between the before column and the after column of a zone.
const _columnGap = 12.0;

/// The screen of one visit: for each zone record a before photo, an after photo, the previous photos, and a note.
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
          ..showSnackBar(SnackBar(content: Text(message)));
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
              appBar: AppBar(
                title: visit == null
                    ? null
                    : Text(
                        l10n.visitDateLabel(
                          DateTime(visit.visitDate.year, visit.visitDate.month, visit.visitDate.day),
                        ),
                      ),
              ),
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

  /// Asks before the person leaves with a note that storage did not take, and closes the screen on a yes.
  Future<void> _confirmLeave(BuildContext context) async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final leaves = await showConfirmDialog(
      context: context,
      title: l10n.visitLeaveUnsavedDialogTitle,
      message: l10n.visitLeaveUnsavedDialogMessage,
      confirmLabel: l10n.visitLeaveUnsavedConfirmButton,
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
        child: Text(context.l10n.visitReportOpenButton),
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
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      child: ColoredBox(
        color: colors.errorContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.visitUnsavedMessage, style: TextStyle(color: colors.onErrorContainer)),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: colors.onErrorContainer),
                  onPressed: () => unawaited(context.read<VisitCaptureCubit>().saveAgain()),
                  child: Text(l10n.visitSaveAgainButton),
                ),
              ),
            ],
          ),
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
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

/// One zone of the visit: its name, the two photo controls, the previous photos, and the note.
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
            child: Text(record.zoneName, style: Theme.of(context).textTheme.titleMedium),
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
          _NoteField(zoneId: record.zoneId, note: record.note, readOnly: isCapturing),
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
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            child: Text(label, textAlign: TextAlign.center),
          ),
        ],
      ),
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
        Text(
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

/// The note of one zone. Each edit goes to the cubit, which saves it at once.
///
/// The label is a text of its own above the field, as in `NameField`, so that a large text size cuts nothing.
class _NoteField extends StatefulWidget {
  const new({required this.zoneId, required this.note, required this.readOnly});

  final String zoneId;

  /// The note that the field holds when it opens. A later value does not replace what the person typed.
  final String note;
  final bool readOnly;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final _controller = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.noteFieldLabel, style: Theme.of(context).textTheme.labelLarge),
          TextField(
            controller: _controller,
            readOnly: widget.readOnly,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: null,
            onChanged: (note) => unawaited(context.read<VisitCaptureCubit>().editNote(widget.zoneId, note)),
          ),
        ],
      ),
    );
  }
}
