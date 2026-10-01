// Every field of the class is final, and `package:meta`, which has `@immutable`, is not a dependency.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

part of 'report_link_cubit.dart';

enum ReportLinkStatus {
  /// The cubit reads whether the flavor publishes and whether the client has a page.
  loading,

  /// The flavor has no backend, so the screen offers the PDF only.
  unavailable,

  /// A link share can start.
  ready,

  /// The publish job of the visit runs, or waits for its first run. The share sheet opens when it is done.
  publishing,

  /// The publish job failed for a reason that a retry can fix, and the queue runs it again after its delay.
  waitingForRetry,

  /// The publish job stopped, or the request did not reach the queue. [ReportLinkState.failure] holds the reason of
  /// a job that stopped.
  failed,

  /// The report is published, and the share sheet did not open with its link.
  shareFailed,
}

final class ReportLinkState {
  const new({this.status = ReportLinkStatus.loading, this.isFirstShare = false, this.failure});

  final ReportLinkStatus status;

  /// Whether the client has no page yet, so that this share makes the first link of the client. The screen then
  /// says, before the share, that anyone with the link can open the reports.
  final bool isFirstShare;

  /// Why the publish job stopped, while [status] is [ReportLinkStatus.failed]. It is null when the request did not
  /// reach the queue.
  final PublishFailure? failure;

  /// Whether a link share can start. A share while the job waits for its retry runs the job again now.
  bool get canShare => switch (status) {
    ReportLinkStatus.ready ||
    ReportLinkStatus.waitingForRetry ||
    ReportLinkStatus.failed ||
    ReportLinkStatus.shareFailed => true,
    ReportLinkStatus.loading || ReportLinkStatus.unavailable || ReportLinkStatus.publishing => false,
  };

  @override
  bool operator ==(Object other) =>
      other is ReportLinkState &&
      other.status == status &&
      other.isFirstShare == isFirstShare &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(status, isFirstShare, failure);

  @override
  String toString() => 'ReportLinkState(${status.name}, $isFirstShare, ${failure?.name})';
}
