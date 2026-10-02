import 'dart:async';
import 'dart:developer';
import 'dart:math' show Random, min;
import 'dart:typed_data';

import 'package:kkomkkomi/application/client_page.dart';
import 'package:kkomkkomi/application/client_repository.dart';
import 'package:kkomkkomi/application/clock.dart';
import 'package:kkomkkomi/application/company_profile_repository.dart';
import 'package:kkomkkomi/application/id_generator.dart';
import 'package:kkomkkomi/application/identity.dart';
import 'package:kkomkkomi/application/network_monitor.dart';
import 'package:kkomkkomi/application/photo_store.dart';
import 'package:kkomkkomi/application/publish_job.dart';
import 'package:kkomkkomi/application/publish_repository.dart';
import 'package:kkomkkomi/application/publisher.dart';
import 'package:kkomkkomi/application/visit_repository.dart';
import 'package:kkomkkomi/application/without_location.dart';
import 'package:kkomkkomi/domain/domain.dart';

/// Starts a timer that calls [callback] once after [delay], as `Timer.new` does.
typedef StartTimer = Timer Function(Duration delay, void Function() callback);

/// Waits for [delete], a delete of the backend, within a time limit, and fails when it does not answer in time.
///
/// A timeout does not cancel the delete, so the runner keeps one that does not answer in time until it ends, and
/// calls [onLateSuccess] when it then ends with success.
typedef TimedDelete = Future<void> Function(Future<void> delete, {Future<void> Function()? onLateSuccess});

/// The path of the object that holds [photo], the photo in [slot] of the zone with [zoneId], in the report of the
/// visit with [visitId] under the page with [pageId].
///
/// The path depends on nothing else, so a repeated upload of one photo file writes the object that an earlier upload
/// wrote, with the same bytes. The name of the photo file is part of the path, because a retake is a new file: an
/// upload of the old photo that is still on its way after a timeout then writes its own object, which the report no
/// longer names, and never the object of the retake.
String photoObjectPath({
  required String pageId,
  required String visitId,
  required String zoneId,
  required PhotoSlot slot,
  required PhotoRef photo,
}) {
  final fileName = photo.path.substring(photo.path.lastIndexOf('/') + 1);
  final extension = fileName.lastIndexOf('.');
  final name = extension > 0 ? fileName.substring(0, extension) : fileName;
  return 'clientPages/$pageId/$visitId/$zoneId-${slot.name}-$name.jpg';
}

/// Publishes visits as reports under the client pages, and revokes and reissues client pages.
///
/// Each request is a job in the [PublishRepository], so a job outlives the app process. The queue runs one job at a
/// time, oldest first. A job that fails for a reason that a retry can fix runs again after a delay that grows with
/// each failure, and a job that fails for another reason stops with that reason. The queue runs every pending job at
/// once when it starts and each time the network returns.
///
/// Each step of a job is safe to repeat, so a job that stopped in the middle runs again from its first step. A photo
/// that reached the backend is not uploaded again while the visit holds the same photo file.
final class PublishQueue {
  new({
    required this._repository,
    required this._clients,
    required this._visits,
    required this._companyProfile,
    required this._photoStore,
    required this._publisher,
    required this._identity,
    required this._networkMonitor,
    required this._idGenerator,
    required this._clock,
    Random? random,
    this._startTimer = Timer.new,
    this._stepTimeout = defaultStepTimeout,
  }) : _random = random ?? Random.secure();

  /// The delay after the first failure of a job.
  static const firstRetryDelay = Duration(seconds: 5);

  /// The longest delay between two runs of a job.
  static const longestRetryDelay = Duration(minutes: 15);

  /// How long a step may take before the queue treats it as a failure that a retry can fix.
  ///
  /// A write of the backend can wait for the network without an end, so without a limit one job would stop the queue.
  /// An upload that does not answer in time is cancelled, and the queue waits up to this time again for its end, so
  /// an upload step takes at most twice this time.
  static const defaultStepTimeout = Duration(minutes: 3);

  /// The delay before the next run of a job that failed [failures] times, which doubles with each failure from
  /// [firstRetryDelay] up to [longestRetryDelay].
  static Duration retryDelay(int failures) {
    final factor = 1 << min(failures - 1, 20);
    final delay = firstRetryDelay * factor;
    return delay > longestRetryDelay ? longestRetryDelay : delay;
  }

  final PublishRepository _repository;
  final ClientRepository _clients;
  final VisitRepository _visits;
  final CompanyProfileRepository _companyProfile;
  final PhotoStore _photoStore;
  final Publisher _publisher;
  final Identity _identity;
  final NetworkMonitor _networkMonitor;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final Random _random;
  final StartTimer _startTimer;
  final Duration _stepTimeout;

  final _updates = StreamController<PublishJob>.broadcast();
  StreamSubscription<void>? _network;
  Timer? _timer;
  Future<void>? _running;
  var _runAgain = false;
  var _disposed = false;
  var _held = false;

  /// The objects whose upload a cancel did not end, while the upload is on its way.
  final _unsettled = <String>{};

  /// Each job after a run of it changed its state, for a screen that shows where a job is and why it stopped.
  Stream<PublishJob> get updates => _updates.stream;

  /// Whether the flavor has a backend. Every job of a flavor without one stops with [PublishFailure.unavailable].
  bool get isAvailable => _publisher.isAvailable;

  /// Whether the client with [clientId] has an open page, which it gets at its first publish.
  Future<bool> hasOpenPage(String clientId) async => await _repository.openPageOf(clientId) != null;

  /// Runs every pending job now, the jobs that an earlier launch left too, and then each time the network returns.
  Future<void> start() async {
    _network ??= _networkMonitor.restored.listen(
      (_) => unawaited(_resume()),
      // A failure of the network state leaves the retry delays to run the jobs.
      onError: (Object error) => log('The network state is unavailable: $error'),
    );
    await _resume();
  }

  /// Stops the timer and the network events. The queue runs no job after this.
  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _network?.cancel();
    await _updates.close();
  }

  /// Adds a job that publishes the visit with [visitId] under the open page of its client, and returns the job.
  ///
  /// The client gets its page at its first publish. When a job for the same visit and page is pending, the queue
  /// adds none and restarts that job. When that job runs now, it runs again after this run, so that the visit as it
  /// is now reaches the backend. Throws an [ArgumentError] when no visit has [visitId].
  Future<PublishJob> publishVisit(String visitId) async {
    final visit = await _visits.visitById(visitId);
    if (visit == null) throw ArgumentError.value(visitId, 'visitId', 'No visit has this ID');
    final page = await _repository.openPageOf(visit.clientId, create: () => _newPage(visit.clientId));
    final job = await _repository.enqueue(
      PublishJob(
        id: _idGenerator.newId(),
        kind: PublishJobKind.publish,
        pageId: page!.id,
        visitId: visit.id,
        createdAt: _clock.now(),
      ),
    );
    unawaited(_run());
    return job;
  }

  /// Removes access to the open page of the client with [clientId], and returns that page as revoked.
  ///
  /// The pending publish jobs of the page stop, and a job marks the page as revoked on the backend and deletes the
  /// photos that the app uploaded under it. Returns null when the client has no open page.
  Future<ClientPage?> revokeClientPage(String clientId) async {
    final page = await _repository.openPageOf(clientId);
    if (page == null) return null;
    final now = _clock.now();
    // A revoke or a reissue that came first between the read and this call leaves the client without this page.
    if (!await _repository.revoke(page, at: now, revokeJob: _revokeJob(page, now))) return null;
    unawaited(_run());
    return page.revoke(now);
  }

  /// Gives the client with [clientId] a new page, revokes its old page as [revokeClientPage] does, and publishes
  /// again under the new page each visit that was published or waiting under the old one. Returns the new page.
  Future<ClientPage> reissueClientPage(String clientId) async {
    final old = await _repository.openPageOf(clientId);
    if (old == null) return (await _repository.openPageOf(clientId, create: () => _newPage(clientId)))!;
    final now = _clock.now();
    final replacement = _newPage(clientId);
    final revoked = await _repository.revoke(
      old,
      at: now,
      revokeJob: _revokeJob(old, now),
      replacement: replacement,
      republish: (visitId) => PublishJob(
        id: _idGenerator.newId(),
        kind: PublishJobKind.publish,
        pageId: replacement.id,
        visitId: visitId,
        createdAt: now,
      ),
    );
    // A revoke or a reissue that came first leaves the old page revoked, and the client keeps the page that it has.
    if (!revoked) return (await _repository.openPageOf(clientId, create: () => _newPage(clientId)))!;
    unawaited(_run());
    return replacement;
  }

  /// Whether [hold] stopped the queue, until [release].
  bool get isHeld => _held;

  /// Stops the queue, and completes when the job that runs now ended.
  ///
  /// Until [release], no job runs: not at a request, not at its retry delay, and not when the network returns. A
  /// request still adds its job, which runs after the release. A call while the queue is held completes at once.
  Future<void> hold() async {
    _held = true;
    _timer?.cancel();
    _timer = null;
    await _running;
  }

  /// Lets the queue run its jobs again after [hold], and runs the pending jobs whose retry delay has passed.
  void release() {
    if (!_held) return;
    _held = false;
    unawaited(_run());
  }

  /// Deletes from the backend everything that the app published under each of its pages, open and revoked: first
  /// the objects of the photos that it uploaded or started to upload, then the reports, then the pages.
  ///
  /// Before the first delete, every pending job stops with [PublishFailure.deletion], so that no job publishes again
  /// what this call deleted, also after a failure or a restart of the app. A later publish request, which the person
  /// makes, starts a new job. The objects come first, because the rules of the photos read the page to find its owner.
  /// The reports are those of every visit that a job ever published under the page, since a job that stopped may have
  /// written its report before it stopped, and the rules do not let the app list the reports of a revoked page. Each
  /// delete is safe to repeat, so a call after a failed one deletes what is left. The local pages and jobs stay: the
  /// caller erases the local data after this call.
  ///
  /// Each delete runs through [timed], which the deletion of all data gives so that it keeps a delete that does not
  /// answer in time until the delete ends. The removal of the record of a photo is the [TimedDelete] `onLateSuccess`
  /// of its delete, so that a delete that ends late leaves no record of an object that is gone. Without [timed], a
  /// delete fails after the step timeout of the queue.
  ///
  /// Throws a [StateError] while the queue is not held, because a job that runs at the same time could write again
  /// what this call deleted. Throws a [PublishException] that a retry can fix while an upload that a cancel did not
  /// end is on its way, before any delete, because that upload could create its object after the delete.
  Future<void> deletePublished({TimedDelete? timed}) async {
    final run = timed ?? (delete, {onLateSuccess}) => _step(delete);
    if (!_held) throw StateError('The queue must be held while the published data is deleted');
    if (_unsettled.isNotEmpty) {
      throw PublishException(PublishErrorKind.transient, 'An upload to ${_unsettled.first} has not ended');
    }
    final pages = await _repository.pages();
    if (pages.isEmpty) return;
    // The rules let only the signed-in owner delete, and the answer also means that the backend started.
    if (await _step(_identity.currentUserId()) == null) {
      throw const PublishException(PublishErrorKind.transient, 'No user is signed in');
    }
    // A delete may reach the backend even when its answer does not reach the app, so the jobs stop before the first.
    await _repository.stopPendingJobs(PublishFailure.deletion);
    for (final page in pages) {
      for (final objectPath in await _repository.uploadedObjects(page.id)) {
        _expectSettled(objectPath);
        Future<void> forget() => _repository.removeUploadedPhoto(pageId: page.id, objectPath: objectPath);
        await run(_publisher.deletePhoto(objectPath), onLateSuccess: forget);
        await forget();
      }
    }
    for (final page in pages) {
      final visitIds = {for (final job in await _repository.jobsOfPage(page.id)) ?job.visitId};
      for (final visitId in visitIds) {
        await run(_publisher.deleteReport(pageId: page.id, visitId: visitId));
      }
    }
    for (final page in pages) {
      await run(_publisher.deletePage(page.id));
    }
  }

  ClientPage _newPage(String clientId) =>
      ClientPage(id: newPageId(_random), clientId: clientId, createdAt: _clock.now());

  PublishJob _revokeJob(ClientPage page, DateTime now) =>
      PublishJob(id: _idGenerator.newId(), kind: PublishJobKind.revoke, pageId: page.id, createdAt: now);

  Future<void> _resume() async {
    if (_held) return;
    try {
      await _repository.clearRetryDelays();
    } on Object catch (error, stackTrace) {
      log('The publish queue did not clear its delays: $error', stackTrace: stackTrace);
    }
    await _run();
  }

  /// Runs the jobs that are due, or makes the run that is on its way look at the jobs again when it ends.
  Future<void> _run() {
    if (_disposed || _held) return Future.value();
    if (_running case final running?) {
      _runAgain = true;
      return running;
    }
    _timer?.cancel();
    _timer = null;
    // The run is marked before it starts, because a store that fails at once ends the run before its first wait.
    final done = Completer<void>();
    _running = done.future;
    unawaited(_runDueJobs().whenComplete(done.complete));
    return done.future;
  }

  Future<void> _runDueJobs() async {
    try {
      while (!_disposed && !_held) {
        _runAgain = false;
        for (final job in await _repository.pendingJobs()) {
          // A hold waits for the job that runs now, and no other job starts.
          if (_disposed || _held) return;
          if (job.nextAttemptAt case final at? when at.isAfter(_clock.now())) continue;
          await _runJob(job);
        }
        final pending = await _repository.pendingJobs();
        // A request that came while the jobs were read again is not in what the run read, so the run goes on.
        if (_runAgain) continue;
        _scheduleNextRun(pending);
        return;
      }
    } on Object catch (error, stackTrace) {
      // A failure of local storage leaves the jobs as they are, and the next start or network event runs them.
      log('The publish queue stopped: $error', stackTrace: stackTrace);
    } finally {
      // The run ends in the same step in which it last looked at `_runAgain`, so no request falls between the two.
      _running = null;
    }
  }

  void _scheduleNextRun(List<PublishJob> pending) {
    if (_disposed || _held || pending.isEmpty) return;
    final now = _clock.now();
    final next = pending.map((job) => job.nextAttemptAt ?? now).reduce((a, b) => a.isBefore(b) ? a : b);
    final delay = next.difference(now);
    _timer = _startTimer(delay.isNegative ? Duration.zero : delay, () => unawaited(_run()));
  }

  Future<void> _runJob(PublishJob job) async {
    PublishJob result;
    try {
      if (!_publisher.isAvailable) throw const _Stop(PublishFailure.unavailable);
      final ownerUid = await _step(_identity.currentUserId());
      if (ownerUid == null) throw const PublishException(PublishErrorKind.transient, 'No user is signed in');
      switch (job.kind) {
        case PublishJobKind.publish:
          await _publish(job, ownerUid);
        case PublishJobKind.revoke:
          await _revoke(job, ownerUid);
      }
      result = job.succeed();
    } on _Stop catch (stop) {
      result = job.fail(stop.reason);
    } on Object catch (error, stackTrace) {
      if (error is PublishException && error.kind == PublishErrorKind.refused) {
        log('A publish job was refused: $error');
        result = job.fail(PublishFailure.refused);
      } else {
        // A timeout, a missing network, and every failure that the queue cannot name can pass with time, so the job
        // runs again.
        log('A publish job will run again: $error', stackTrace: stackTrace);
        result = job.retryAt(_clock.now().add(retryDelay(job.attempts + 1)));
      }
    }
    // The run read the job before its steps. A revoke that stopped the job during them, or a publish request that
    // restarted it with a new generation, changed the stored job, and the store saves over the job only while it is
    // the pending job of the same generation. So the run never undoes a stop or loses a restart, and a restarted job
    // runs again with the visit as it is now.
    if (await _repository.saveJob(result) && !_disposed) _updates.add(result);
  }

  Future<T> _step<T>(Future<T> step) => step.timeout(_stepTimeout);

  Future<PublishedPage> _pageContent(ClientPage page, String ownerUid) async {
    // A page belongs to a client, and a client is deleted only with every page and job, while the queue is held.
    final client = (await _clients.clientById(page.clientId))!;
    final profile = await _companyProfile.load();
    return PublishedPage(
      ownerUid: ownerUid,
      companyName: profile?.name,
      clientName: client.name,
      createdAt: page.createdAt,
    );
  }

  Future<void> _publish(PublishJob job, String ownerUid) async {
    // A job belongs to a page, and a publish job to a visit. A page or a visit is deleted only with every job, while
    // the queue is held.
    final page = (await _repository.pageById(job.pageId))!;
    if (page.isRevoked) throw const _Stop(PublishFailure.revoked);
    final visit = (await _visits.visitById(job.visitId!))!;
    // The rules of the reports and of the photos read the page, so the page goes first.
    await _step(_publisher.writePage(page.id, await _pageContent(page, ownerUid)));
    final zones = <PublishedZone>[];
    for (final record in visit.zoneRecords) {
      if (!record.hasContent) continue;
      zones.add(
        PublishedZone(
          name: record.zoneName,
          note: record.note.trim(),
          beforePhoto: await _upload(page.id, visit.id, record, PhotoSlot.before),
          afterPhoto: await _upload(page.id, visit.id, record, PhotoSlot.after),
        ),
      );
    }
    await _step(
      _publisher.writeReport(
        pageId: page.id,
        visitId: visit.id,
        // The time of the request, which a job keeps, so that a job that runs again writes the same report.
        report: PublishedReport(visitDate: visit.visitDate, publishedAt: job.createdAt, zones: zones),
      ),
    );
    // An object of the visit that the report no longer names, such as the photo before a retake, is deleted after
    // the report, so that no report ever names a deleted object.
    final named = {
      for (final zone in zones) ...[?zone.beforePhoto, ?zone.afterPhoto],
    };
    final ofVisit = 'clientPages/${page.id}/${visit.id}/';
    for (final objectPath in await _repository.uploadedObjects(page.id)) {
      if (!objectPath.startsWith(ofVisit) || named.contains(objectPath)) continue;
      await _deletePhoto(page.id, objectPath);
    }
  }

  /// Uploads the photo in [slot] of [record] and returns the path of its object, or null when the slot is empty.
  Future<String?> _upload(String pageId, String visitId, ZoneRecord record, PhotoSlot slot) async {
    final photo = record.photoIn(slot);
    if (photo == null) return null;
    final objectPath = photoObjectPath(
      pageId: pageId,
      visitId: visitId,
      zoneId: record.zoneId,
      slot: slot,
      photo: photo,
    );
    if (await _repository.uploadedPhoto(pageId: pageId, objectPath: objectPath) == photo.path) return objectPath;
    _expectSettled(objectPath);
    final Uint8List bytes;
    try {
      bytes = await _photoStore.read(photo);
    } on Object catch (error) {
      log('A photo of a publish job did not read: $error');
      // A retake deletes the file of the photo that it replaces, so a visit that holds another photo now is
      // published again from the start.
      final current = (await _visits.visitById(visitId))!.recordFor(record.zoneId)?.photoIn(slot);
      if (current != photo) throw const PublishException(PublishErrorKind.transient, 'The photo was replaced');
      throw const _Stop(PublishFailure.photoMissing);
    }
    // The result of `withoutLocation` is never longer than the file, so a file within the limit stays within it.
    if (bytes.length > maxPhotoBytes) throw const _Stop(PublishFailure.photoTooLarge);
    final Uint8List clean;
    try {
      // The photo store removes the location of a new photo. A photo that it stored before that change still holds
      // it, so the queue removes it again before the upload (issue 20).
      clean = withoutLocation(bytes);
    } on FormatException catch (error) {
      log('A photo of a publish job is no well-formed JPEG: $error');
      throw const _Stop(PublishFailure.photoNotJpeg);
    }
    // The object is recorded before the upload, because an upload that does not answer in time can still arrive
    // later, and a cleanup or a revoke must know every object that may exist.
    await _repository.recordUploadIntent(pageId: pageId, objectPath: objectPath, photoPath: photo.path);
    final cancel = Completer<void>();
    final upload = _publisher.uploadPhoto(objectPath, clean, cancel: cancel.future);
    try {
      await _step(upload);
    } on TimeoutException {
      // A timeout does not stop the upload, which could then create its object after a revoke or a cleanup deleted
      // the path (issue 13). So the queue cancels it and waits for its end before the step counts as failed. An
      // upload that arrived anyway counts as arrived.
      cancel.complete();
      try {
        await _step(upload);
      } on TimeoutException {
        // The upload did not end after the cancel either. Until it ends, no cleanup, revoke, or upload acts on its
        // object, so its record stays and a later run deletes the object if it arrived.
        _unsettled.add(objectPath);
        upload.whenComplete(() => _unsettled.remove(objectPath)).ignore();
        rethrow;
      }
    }
    await _repository.saveUploadedPhoto(pageId: pageId, objectPath: objectPath, photoPath: photo.path);
    return objectPath;
  }

  /// Fails with a failure that a retry can fix while an upload to [objectPath] that a cancel did not end is on its way.
  void _expectSettled(String objectPath) {
    if (_unsettled.contains(objectPath)) {
      throw PublishException(PublishErrorKind.transient, 'An upload to $objectPath has not ended');
    }
  }

  /// Deletes the object at [objectPath] and then its record, after every upload to it ended.
  Future<void> _deletePhoto(String pageId, String objectPath) async {
    _expectSettled(objectPath);
    await _step(_publisher.deletePhoto(objectPath));
    await _repository.removeUploadedPhoto(pageId: pageId, objectPath: objectPath);
  }

  Future<void> _revoke(PublishJob job, String ownerUid) async {
    final page = (await _repository.pageById(job.pageId))!;
    // The time of the revoke, which the page keeps, so that a job that runs again writes the same page.
    await _step(_publisher.revokePage(page.id, await _pageContent(page, ownerUid), revokedAt: page.revokedAt!));
    for (final objectPath in await _repository.uploadedObjects(page.id)) {
      await _deletePhoto(page.id, objectPath);
    }
  }
}

/// A job stops for [reason], which a retry cannot fix.
final class _Stop implements Exception {
  const new(this.reason);

  final PublishFailure reason;
}
