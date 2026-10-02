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
/// A step that fails stops the deletion before the next one, so the data on the device stays until the backend holds
/// nothing of the person, and the person can try again. Each call runs every step again, because a share between two
/// calls can publish again, and every step is safe to repeat: a delete of what is gone changes nothing, and the rules
/// allow it for any signed-in user. A call after the account is gone signs in with a new account, which the call
/// deletes again.
///
/// The publish queue is held while the deletion runs, so that no job writes again what a step deleted, and the first
/// step stops every pending job in storage before its first delete, so that none runs after a failure or a restart.
/// The queue runs again when the call ends, whether it completed or failed, so a share that the person starts later
/// publishes again. In a flavor without a backend, only the data on the device is deleted.
///
/// A delete of the account that does not answer in time fails the account step, but the delete goes on, because a
/// timeout does not cancel it. Until it ends, the queue stays held, so no share publishes under a user ID that the
/// delete may still remove, and a next call starts no second delete: it waits for this one, as long as a step may
/// take, and names the account step again when it is still on its way. When the delete ends with success, the queue
/// stays held, because the account is gone, and the next call goes on with the data on the device. When it ends with a
/// failure, the account still exists, so the queue runs again and the next call runs every step, as after any other
/// failure. This is the shape of the uploads that a cancel did not end in [PublishQueue] (issue 13).
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

  /// The delete of the account that did not answer in time and has not ended, or null when none is on its way.
  Future<void>? _unsettledAccountDeletion;

  /// Whether a delete of the account that did not answer in time ended with success, and the data on the device is
  /// not erased yet.
  var _accountGone = false;

  /// Deletes everything, and completes when the device is as a first launch leaves it.
  ///
  /// Throws a [DeletionFailure] that names the step that failed.
  Future<void> call() async {
    await _publishQueue.hold();
    final hasBackend = _publishQueue.isAvailable;
    var step = DeletionStep.publishedData;
    try {
      if (_unsettledAccountDeletion case final unsettled?) {
        step = DeletionStep.account;
        await unsettled.timeout(_stepTimeout);
      } else if (!_accountGone) {
        if (hasBackend) await _publishQueue.deletePublished();
        step = DeletionStep.account;
        if (hasBackend) await _deleteAccount();
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
      // While the account may still be deleted, or is gone, a job must not publish under its user ID or a new one.
      if (_unsettledAccountDeletion == null && !_accountGone) _publishQueue.release();
    }
  }

  /// Deletes the account, and keeps a delete that does not answer within the step timeout until it ends.
  Future<void> _deleteAccount() {
    final deletion = _identity.deleteAccount();
    return deletion.timeout(
      _stepTimeout,
      onTimeout: () {
        _unsettledAccountDeletion = deletion;
        deletion
            .then(
              (_) {
                _unsettledAccountDeletion = null;
                _accountGone = true;
              },
              onError: (Object error) {
                log('The late delete of the account failed: $error');
                _unsettledAccountDeletion = null;
                // The account still exists, so the person can try again, and the queue runs again.
                _publishQueue.release();
              },
            )
            .ignore();
        throw TimeoutException('The delete of the account did not answer in time', _stepTimeout);
      },
    );
  }
}
