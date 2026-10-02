import 'package:kkomkkomi/application/id_generator.dart';
import 'package:kkomkkomi/application/open_capture.dart';
import 'package:kkomkkomi/application/photo_capture.dart';
import 'package:kkomkkomi/application/photo_store.dart';
import 'package:kkomkkomi/application/visit_repository.dart';
import 'package:kkomkkomi/domain/domain.dart';

/// What the start of the app did with the photo of a capture whose answer the app lost.
final class LostCaptureRecovery {
  const new({required this.visitId, this.failure});

  /// The visit that the capture was for.
  final String visitId;

  /// What kept the photo out of the visit, or null when the visit holds the photo.
  final Object? failure;

  /// Whether the visit holds the photo.
  bool get isRecovered => failure == null;
}

/// Puts the photo of a capture whose answer the app lost into the slot that the capture was for.
///
/// The system can end the app while the camera app is open, and the photo of that capture then does not reach the
/// visit screen. The visit screen stores the [OpenCapture] before the camera opens, so the next start of the app
/// knows the visit, the zone, and the slot of the photo that the camera kept.
final class RecoverLostCapture {
  const new({
    required this._openCaptures,
    required this._visits,
    required this._photoCapture,
    required this._photoStore,
    required this._idGenerator,
    this._retryDelays = defaultRetryDelays,
  });

  /// The waits before each new question to the camera while it has no photo for a stored capture: 2 seconds in all.
  ///
  /// The camera of Android writes the lost answer on a background thread after the app started again, so the first
  /// question can come before the answer. The length is an estimate, not a measurement on a device.
  static const defaultRetryDelays = [
    Duration(milliseconds: 500),
    Duration(milliseconds: 500),
    Duration(milliseconds: 500),
    Duration(milliseconds: 500),
  ];

  final OpenCaptureRepository _openCaptures;
  final VisitRepository _visits;
  final PhotoCapture _photoCapture;
  final PhotoStore _photoStore;
  final IdGenerator _idGenerator;
  final List<Duration> _retryDelays;

  /// Asks the camera for the lost photo of the stored capture, keeps its file, saves the visit with it, and removes
  /// the stored capture.
  ///
  /// Returns null when no capture is stored, when the stored capture is for a visit or a zone record that does not
  /// exist, and when the camera of the platform keeps no lost photo. In those two last cases the stored capture is
  /// removed without a question to the camera, and nothing else changes.
  ///
  /// While the camera has no photo for the stored capture, it is asked again after each of the retry delays. When it
  /// still has none, the method returns null and keeps the stored capture, so that the next start asks again: an
  /// answer that came late stays with the camera until the next capture opens it, and the next capture stores its own
  /// capture first. A capture that ended without a photo, because the person closed the camera or the camera failed,
  /// also leaves the stored capture until the next capture replaces it.
  ///
  /// Returns a [LostCaptureRecovery] with its failure when the photo store or storage did not take the photo: the
  /// camera gave its answer only once, so the stored capture is removed then too. A photo that the slot already held
  /// is replaced, and its file is deleted after storage took the new photo.
  ///
  /// Throws when the stored capture or the visit cannot be read and when the camera cannot be asked. The stored
  /// capture then stays, so that the next start asks again.
  Future<LostCaptureRecovery?> call() async {
    final capture = await _openCaptures.load();
    if (capture == null) return null;
    final visit = await _visits.visitById(capture.visitId);
    final record = visit?.recordFor(capture.zoneId);
    if (visit == null || record == null || !_photoCapture.keepsLostPhotos) {
      await _openCaptures.clear();
      return null;
    }
    var picked = await _photoCapture.retrieveLostPhoto();
    for (final delay in _retryDelays) {
      if (picked != null) break;
      await Future<void>.delayed(delay);
      picked = await _photoCapture.retrieveLostPhoto();
    }
    if (picked == null) return null;
    final recovery = await _keep(picked, visit, record, capture.slot);
    try {
      await _openCaptures.clear();
    } on Exception {
      // The camera gave its answer away, so the next start finds no photo for the stored capture, and the next capture
      // replaces it. The visit already holds what the recovery says.
    }
    return recovery;
  }

  Future<LostCaptureRecovery> _keep(String picked, Visit visit, ZoneRecord record, PhotoSlot slot) async {
    final PhotoRef photo;
    try {
      photo = await _photoStore.save(sourcePath: picked, visitId: visit.id, photoId: _idGenerator.newId());
    } on Exception catch (error) {
      return LostCaptureRecovery(visitId: visit.id, failure: error);
    }
    try {
      await _visits.save(visit.withRecord(record.withPhoto(slot, photo)));
    } on Exception catch (error) {
      await _deleteFile(photo);
      return LostCaptureRecovery(visitId: visit.id, failure: error);
    }
    // The old file goes only now, so that a failed save leaves the slot with the photo that storage names.
    if (record.photoIn(slot) case final replaced?) await _deleteFile(replaced);
    return LostCaptureRecovery(visitId: visit.id);
  }

  /// Deletes the file of [photo], which no record names. A file that stays takes space and breaks nothing, so a
  /// failure here does not change the answer.
  Future<void> _deleteFile(PhotoRef photo) async {
    try {
      await _photoStore.delete(photo);
    } on Exception {
      return;
    }
  }
}
