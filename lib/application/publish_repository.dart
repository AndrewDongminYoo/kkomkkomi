import 'package:kkomkkomi/application/client_page.dart';
import 'package:kkomkkomi/application/publish_job.dart';

/// Stores the client pages, the publish jobs, and which photo file the app uploaded to which object.
abstract interface class PublishRepository {
  /// The open page of the client with [clientId], or null when the client has none.
  ///
  /// When the client has none and [create] is given, stores the page that [create] makes and returns it, in one
  /// transaction, so that a client never gets two open pages.
  Future<ClientPage?> openPageOf(String clientId, {ClientPage Function()? create});

  /// The page with [id], or null when none exists.
  Future<ClientPage?> pageById(String id);

  /// Adds [job] and returns it.
  ///
  /// When a pending publish job for the same page and visit exists, adds nothing and returns that job after
  /// [PublishJob.restart], so that a visit is not published twice at one time.
  Future<PublishJob> enqueue(PublishJob job);

  /// Revokes [page] at [at] and adds [revokeJob], in one transaction, and returns whether it did.
  ///
  /// Each pending publish job of [page] fails with [PublishFailure.revoked]. When [replacement] is given, it is stored
  /// as the new open page of the client, and [republish] makes a job for each visit that had a pending or done publish
  /// job under [page], in the order of their first jobs. Returns false, and changes nothing, when [page] is no longer
  /// open, for example because another revoke came first.
  Future<bool> revoke(
    ClientPage page, {
    required DateTime at,
    required PublishJob revokeJob,
    ClientPage? replacement,
    PublishJob Function(String visitId)? republish,
  });

  /// Saves [job] in place of the stored job with its ID while the stored job is pending, and returns whether it did.
  ///
  /// A job that ended or stopped keeps its state, so a run that read a job before a revoke stopped it cannot make it
  /// done or pending again.
  Future<bool> saveJob(PublishJob job);

  /// The pending jobs, oldest first.
  Future<List<PublishJob>> pendingJobs();

  /// Every job of the page with [pageId], oldest first.
  Future<List<PublishJob>> jobsOfPage(String pageId);

  /// Clears the retry delay of every pending job, so that each can run now.
  Future<void> clearRetryDelays();

  /// The path of the photo file that the app uploaded to [objectPath] under the page with [pageId], or null when it
  /// uploaded none.
  Future<String?> uploadedPhoto({required String pageId, required String objectPath});

  /// Records that the photo file at [photoPath] reached [objectPath] under the page with [pageId].
  Future<void> saveUploadedPhoto({required String pageId, required String objectPath, required String photoPath});

  /// The objects that the app uploaded under the page with [pageId] and did not delete, in the order of their paths.
  Future<List<String>> uploadedObjects(String pageId);

  /// Records that the object at [objectPath] under the page with [pageId] is deleted.
  Future<void> removeUploadedPhoto({required String pageId, required String objectPath});
}
