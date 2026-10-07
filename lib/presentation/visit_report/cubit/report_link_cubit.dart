// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:bloc/bloc.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';

part 'report_link_state.dart';

/// Publishes one visit through the publish queue of the app, and shares the link of its report when the report is
/// on the backend.
///
/// The share sheet opens only after the publish job of the visit is done. The job writes the client page first and
/// the report last, so a shared link never opens a page or a report that the backend does not hold yet.
class ReportLinkCubit extends Cubit<ReportLinkState> {
  new({
    required this._visitId,
    required this._visits,
    required this._publishQueue,
    required this._linkShare,
  }) : super(const ReportLinkState());

  final String _visitId;
  final VisitRepository _visits;
  final PublishQueue _publishQueue;
  final LinkShare _linkShare;

  StreamSubscription<PublishJob>? _updates;
  bool Function()? _mayOpenShareSheet;

  /// Reads whether the flavor publishes, and whether the client of the visit has a page.
  ///
  /// When storage does not answer, the state counts the share as the first one, so that the screen shows the notice
  /// once more rather than never.
  Future<void> load() async {
    if (!_publishQueue.isAvailable) {
      _show(const ReportLinkState(status: ReportLinkStatus.unavailable));
      return;
    }
    var isFirstShare = true;
    try {
      // A visit that storage does not have cannot be published, and the share then fails with its own message.
      if (await _visits.visitById(_visitId) case final visit?) {
        isFirstShare = !await _publishQueue.hasOpenPage(visit.clientId);
      }
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
    }
    _show(ReportLinkState(status: ReportLinkStatus.ready, isFirstShare: isFirstShare));
  }

  /// Publishes the visit as it is now, and opens the share sheet with the link of its report when the job is done.
  ///
  /// The state follows the job: [ReportLinkStatus.publishing] while it runs, [ReportLinkStatus.waitingForRetry]
  /// while it waits for a retry, and [ReportLinkStatus.failed] when it stops. A job can take minutes on a field
  /// network, so when it is done the share sheet opens only while [mayOpenShareSheet] answers true, which the screen
  /// answers while it is on top and no other share sheet is on its way. Otherwise the state is
  /// [ReportLinkStatus.published], and the next share publishes the visit again as it is then. A call does nothing
  /// while the state cannot share: see [ReportLinkState.canShare].
  Future<void> share({bool Function()? mayOpenShareSheet}) async {
    if (!state.canShare) return;
    _mayOpenShareSheet = mayOpenShareSheet;
    emit(ReportLinkState(status: ReportLinkStatus.publishing, isFirstShare: state.isFirstShare));
    _stopFollowing();
    // The cubit listens before the request, because the queue can finish the job before the request returns.
    final early = <PublishJob>[];
    PublishJob? requested;
    _updates = _publishQueue.updates.listen((job) {
      if (requested case final requested?) {
        if (_isUpdateOf(requested, job)) unawaited(_follow(job));
      } else {
        early.add(job);
      }
    });
    final PublishJob job;
    try {
      job = await _publishQueue.publishVisit(_visitId);
    } on Object catch (error, stackTrace) {
      // A visit that storage does not have throws an `ArgumentError`, and a failure of storage an `Exception`.
      _report(error, stackTrace);
      _stopFollowing();
      _show(ReportLinkState(status: ReportLinkStatus.failed, isFirstShare: state.isFirstShare));
      return;
    }
    requested = job;
    // The request gave the client its page, so a later share is not the first one.
    _show(const ReportLinkState(status: ReportLinkStatus.publishing));
    for (final update in early) {
      if (_isUpdateOf(job, update)) await _follow(update);
    }
  }

  /// Whether [job] is a change of the job that [requested] names, in the generation that the request made.
  static bool _isUpdateOf(PublishJob requested, PublishJob job) =>
      job.id == requested.id && job.generation == requested.generation;

  Future<void> _follow(PublishJob job) async {
    final isFollowing = state.status == ReportLinkStatus.publishing || state.status == ReportLinkStatus.waitingForRetry;
    if (isClosed || !isFollowing) return;
    switch (job.status) {
      case PublishJobStatus.pending:
        _show(const ReportLinkState(status: ReportLinkStatus.waitingForRetry));
      case PublishJobStatus.failed:
        _stopFollowing();
        _show(ReportLinkState(status: ReportLinkStatus.failed, failure: job.failure));
      case PublishJobStatus.done:
        _stopFollowing();
        if (!(_mayOpenShareSheet?.call() ?? true)) {
          _show(const ReportLinkState(status: ReportLinkStatus.published));
          return;
        }
        try {
          await _linkShare.shareLink(reportLinkOf(pageId: job.pageId, visitId: _visitId));
          _show(const ReportLinkState(status: ReportLinkStatus.ready));
        } on Exception catch (error, stackTrace) {
          _report(error, stackTrace);
          _show(const ReportLinkState(status: ReportLinkStatus.shareFailed));
        }
    }
  }

  /// Stops listening to the queue. The call does not wait for the end of the subscription, because it comes from
  /// inside an update, and the stream ends the subscription only after that update.
  void _stopFollowing() {
    final updates = _updates;
    _updates = null;
    unawaited(updates?.cancel());
  }

  void _show(ReportLinkState next) {
    if (!isClosed) emit(next);
  }

  void _report(Object error, StackTrace stackTrace) {
    if (!isClosed) addError(error, stackTrace);
  }

  @override
  Future<void> close() async {
    await _updates?.cancel();
    _updates = null;
    await super.close();
  }
}
