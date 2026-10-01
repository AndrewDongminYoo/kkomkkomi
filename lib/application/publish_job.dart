// `lib/application/` imports only the domain, so `@immutable` from `package:meta` is not available here. Every
// field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// What a publish job does.
enum PublishJobKind {
  /// Writes the client page, uploads the photos of a visit, and then writes the report of the visit.
  publish,

  /// Marks a client page as revoked and deletes the photos that the app uploaded under it.
  revoke,
}

/// Where a publish job is.
enum PublishJobStatus {
  /// The queue runs the job, now or after its retry delay.
  pending,

  /// Every step of the job reached the backend.
  done,

  /// The job stopped for a reason that a retry cannot fix. [PublishJob.failure] holds the reason.
  failed,
}

/// Why a publish job stopped. A retry cannot fix any of these.
enum PublishFailure {
  /// The flavor has no backend.
  unavailable,

  /// The backend refused the write, for example because its rules do not allow it.
  refused,

  /// The page of the job was revoked before the job reached the backend.
  revoked,

  /// The file of a photo of the visit cannot be read.
  photoMissing,

  /// A photo of the visit is not a JPEG file.
  photoNotJpeg,

  /// A photo of the visit is larger than [maxPhotoBytes].
  photoTooLarge,
}

/// The largest photo that the queue uploads, which is the limit of `storage.rules`.
const int maxPhotoBytes = 5 * 1024 * 1024;

/// One publish or revoke job of the queue.
final class PublishJob {
  new({
    required this.id,
    required this.kind,
    required this.pageId,
    required DateTime createdAt,
    this.visitId,
    this.status = PublishJobStatus.pending,
    this.attempts = 0,
    DateTime? nextAttemptAt,
    this.failure,
  }) : createdAt = createdAt.toUtc(),
       nextAttemptAt = nextAttemptAt?.toUtc();

  final String id;
  final PublishJobKind kind;
  final String pageId;

  /// The visit that a publish job publishes, and null for a revoke job.
  final String? visitId;

  /// The creation time in UTC. The queue runs pending jobs in the order of this time.
  final DateTime createdAt;

  final PublishJobStatus status;

  /// How many runs of the job failed for a reason that a retry can fix.
  final int attempts;

  /// The time in UTC before which the queue does not run the job again, or null for a job that can run now.
  final DateTime? nextAttemptAt;

  /// Why the job stopped, while [status] is [PublishJobStatus.failed].
  final PublishFailure? failure;

  /// This job, done.
  PublishJob succeed() => _copy(status: PublishJobStatus.done, attempts: attempts, nextAttemptAt: null, failure: null);

  /// This job after one more failed run, to run again at [at].
  PublishJob retryAt(DateTime at) =>
      _copy(status: PublishJobStatus.pending, attempts: attempts + 1, nextAttemptAt: at, failure: null);

  /// This job, stopped for [reason].
  PublishJob fail(PublishFailure reason) =>
      _copy(status: PublishJobStatus.failed, attempts: attempts, nextAttemptAt: null, failure: reason);

  /// This job, pending again with its delay and its count of failed runs cleared.
  PublishJob restart() => _copy(status: PublishJobStatus.pending, attempts: 0, nextAttemptAt: null, failure: null);

  PublishJob _copy({
    required PublishJobStatus status,
    required int attempts,
    required DateTime? nextAttemptAt,
    required PublishFailure? failure,
  }) => PublishJob(
    id: id,
    kind: kind,
    pageId: pageId,
    visitId: visitId,
    createdAt: createdAt,
    status: status,
    attempts: attempts,
    nextAttemptAt: nextAttemptAt,
    failure: failure,
  );

  @override
  bool operator ==(Object other) =>
      other is PublishJob &&
      other.id == id &&
      other.kind == kind &&
      other.pageId == pageId &&
      other.visitId == visitId &&
      other.createdAt == createdAt &&
      other.status == status &&
      other.attempts == attempts &&
      other.nextAttemptAt == nextAttemptAt &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(id, kind, pageId, visitId, createdAt, status, attempts, nextAttemptAt, failure);

  @override
  String toString() =>
      'PublishJob($id, ${kind.name}, $pageId, $visitId, ${status.name}, $attempts, $nextAttemptAt, '
      '${failure?.name})';
}
