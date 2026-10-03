import 'dart:async';
import 'dart:developer';

import 'package:kkomkkomi/application/identity.dart';
import 'package:kkomkkomi/application/local_data_repository.dart';
import 'package:kkomkkomi/application/photo_store.dart';
import 'package:kkomkkomi/application/publish_queue.dart';

/// A step of [DeleteAllData], in the order in which it runs.
enum DeletionStep {
  /// The photos, the reports, and the client pages on the backend.
  publishedData,

  /// The anonymous account on the backend.
  account,

  /// The database and the photo files on the device.
  deviceData,
}

/// [DeleteAllData] stopped at [step], because of [cause].
final class DeletionFailure implements Exception {
  const new(this.step, this.cause);

  final DeletionStep step;
  final Object cause;

  @override
  String toString() => 'DeletionFailure(${step.name}, $cause)';
}

/// Deletes everything that the app holds for the person: what it published, the anonymous account, and the data on
/// the device, in that order.
///
/// A step that fails stops deletion before the next one. A device-stage failure can occur after the database erase
/// committed, during VACUUM, checkpoint, or photo-file removal. The person can explicitly try again. Each call runs every step again, because a share between two
/// calls can publish again, and every step is safe to repeat: a delete of what is gone changes nothing, and the rules
/// allow it for any signed-in user. A call after the account is gone signs in with a new account, which the call
/// deletes again.
///
/// The publish queue is held while the deletion runs, so that no job writes again what a step deleted, and the first
/// step stops every pending job in storage before its first delete, so that none runs after a failure or a restart.
/// The queue runs again when the call ends, whether it completed or failed, so a share that the person starts later
/// publishes its requested visit under a fresh ID after a page deletion intent. In a flavor without a backend, only the data on the device is deleted.
///
/// The first step, before any delete, marks every recorded upload as one that may not have arrived
/// ([PublishQueue.forgetArrivedUploads]). A publish skips the upload of a photo whose record says that it arrived, and
/// a deletion can make that record false in more than one way: a delete that answers late, a record whose removal
/// fails after its object went. With the mark gone, the next share uploads every photo again, whatever the deletion
/// did, and the records stay, so every object that may exist is still known.
///
/// Every delete of the backend runs within the step timeout: each photo object, each report, each page, and the
/// account. A delete that does not answer in time fails its step, but it goes on, because a timeout does not cancel
/// it. The deletion keeps every such delete in one place until it ends, as [PublishQueue] keeps the uploads that a
/// cancel did not end (issue 13), and the queue stays held until all of them ended:
///
/// - A photo delete that ends late could otherwise land after a share in the meantime uploaded the photo again to
///   the same path, and remove the object that the new report names.
/// - A delete of the account that ends late could otherwise remove the user ID that such a share published under.
///   When it ends with success, the queue stays held, because the account is gone, and the next call goes on with
///   the data on the device.
/// - A page operation includes intent, remote deletion, durable confirmation, and notifications. A late success
///   still records confirmation before releasing the hold. No late success resumes account or device deletion.
/// - A report delete is also kept until it settles, before a subsequent share can run.
///
/// A next call while a late delete is on its way starts no second delete of it: it waits for every one, as long as a
/// step may take, and names the earliest step that is still on its way when one does not end in that time.
final class DeleteAllData {
  new({
    required this._publishQueue,
    required this._identity,
    required this._localData,
    required this._photoStore,
    this._stepTimeout = PublishQueue.defaultStepTimeout,
  });

  final PublishQueue _publishQueue;
  final Identity _identity;
  final LocalDataRepository _localData;
  final PhotoStore _photoStore;
  final Duration _stepTimeout;

  /// The deletes of the backend that did not answer in time and have not ended, each as a future that completes
  /// without an error when its delete ended, with the step that it belongs to.
  final _lateDeletes = <Future<void>, DeletionStep>{};

  /// Whether a delete of the account that did not answer in time ended with success, and the data on the device is
  /// not erased yet.
  var _accountGone = false;

  /// Whether a call runs, which holds the queue and releases it when it ends.
  var _inCall = false;

  /// Deletes everything, and completes when the device is as a first launch leaves it.
  ///
  /// Throws a [DeletionFailure] that names the step that failed.
  Future<void> call() async {
    await _publishQueue.hold();
    _inCall = true;
    final hasBackend = _publishQueue.isAvailable;
    var step = DeletionStep.publishedData;
    try {
      await _publishQueue.forgetArrivedUploads();
      if (_lateDeletes.isNotEmpty) {
        step = _lateDeletes.values.reduce((a, b) => a.index <= b.index ? a : b);
        await Future.wait(_lateDeletes.keys.toList()).timeout(_stepTimeout);
      }
      if (!_accountGone) {
        step = DeletionStep.publishedData;
        if (hasBackend) {
          await _publishQueue.deletePublished(timed: (delete) => _timed(delete, DeletionStep.publishedData));
        }
        step = DeletionStep.account;
        if (hasBackend) {
          await _timed(_identity.deleteAccount(), DeletionStep.account, onLateSuccess: () => _accountGone = true);
        }
      }
      step = DeletionStep.deviceData;
      // The database goes before the photo files, so that no stored visit names a file that is gone.
      await _localData.eraseAll();
      await _photoStore.deleteAll();
      _accountGone = false;
    } on Object catch (error, stackTrace) {
      // A plugin can fail with an Error, and the person must still see which step failed, so the clause catches
      // every object.
      log('The deletion stopped at ${step.name}: $error', stackTrace: stackTrace);
      Error.throwWithStackTrace(DeletionFailure(step, error), stackTrace);
    } finally {
      _inCall = false;
      _releaseWhenSettled();
    }
  }

  /// Runs [delete], a delete of [step], within the step timeout, and keeps one that does not answer in time until it
  /// ends. [onLateSuccess] runs when such a delete then ends with success.
  Future<void> _timed(Future<void> delete, DeletionStep step, {void Function()? onLateSuccess}) => delete.timeout(
    _stepTimeout,
    onTimeout: () {
      late final Future<void> settled;
      settled = delete
          .then(
            (_) => onLateSuccess?.call(),
            onError: (Object error) => log('A late delete of ${step.name} failed: $error'),
          )
          .whenComplete(() {
            _lateDeletes.remove(settled);
            _releaseWhenSettled();
          });
      _lateDeletes[settled] = step;
      throw TimeoutException('A delete of ${step.name} did not answer in time', _stepTimeout);
    },
  );

  /// Lets the queue run again when no call runs, no late delete is on its way, and the account still exists, so that
  /// no job publishes under a user ID that a late delete may remove, or under a new one before the device is erased.
  void _releaseWhenSettled() {
    if (!_inCall && _lateDeletes.isEmpty && !_accountGone) _publishQueue.release();
  }
}
