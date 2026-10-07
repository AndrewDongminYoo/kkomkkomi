// 📦 Package imports:
import 'package:bloc/bloc.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

part 'visit_capture_state.dart';

/// Loads one visit, and saves each photo, note, status, and reason of its zone records at once.
///
/// Every save holds the whole visit. A note edit, a status change, and a reason edit each go to the repository at the moment of the edit, without a wait
/// for the save before it, and a capture waits for the answer to the newest save before it opens the camera. The
/// repository applies saves in the order of the calls, so the last save that storage takes holds every change
/// before it, and a screen that opens later reads the visit after every save that an earlier screen sent.
class VisitCaptureCubit extends Cubit<VisitCaptureState> {
  new({
    required this._visitId,
    required this._visits,
    required this._clients,
    required this._photoCapture,
    required this._photoStore,
    required this._idGenerator,
    required this._openCaptures,
  }) : super(const VisitCaptureState());

  final String _visitId;
  final VisitRepository _visits;
  final ClientRepository _clients;
  final PhotoCapture _photoCapture;
  final PhotoStore _photoStore;
  final IdGenerator _idGenerator;
  final OpenCaptureRepository _openCaptures;

  /// The answer to the newest save: true when storage took its visit.
  Future<bool> _newestSave = Future.value(true);

  /// Reads the visit, the name of its client, the previous photos of its zones, and the photo directory.
  ///
  /// A visit that storage does not have is a failed load, because no visit is ever deleted. A client that storage
  /// does not give leaves the name out, and the visit shows all the same. A call does nothing while the visit is on
  /// the screen, because storage can be behind the screen while a change is on its way.
  Future<void> load() async {
    if (state.visit != null) return;
    if (state.status != VisitCaptureStatus.loading) emit(const VisitCaptureState());
    try {
      final visit = await _visits.visitById(_visitId);
      if (visit == null) {
        _show(const VisitCaptureState(status: VisitCaptureStatus.loadFailed));
        return;
      }
      final clientName = await _clientNameOf(visit);
      final previousPhotos = await FindPreviousPhotos(visits: _visits)(visit);
      final photoDirectory = await _photoStore.directoryPath();
      _show(
        VisitCaptureState(
          status: VisitCaptureStatus.ready,
          visit: visit,
          clientName: clientName,
          previousPhotos: previousPhotos,
          photoDirectory: photoDirectory,
        ),
      );
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
      _show(const VisitCaptureState(status: VisitCaptureStatus.loadFailed));
    }
  }

  /// The name of the client of [visit], or null when storage does not give the client.
  ///
  /// The name only tells the person where the photos go, so a failure of storage is reported and does not fail the
  /// load.
  Future<String?> _clientNameOf(Visit visit) async {
    try {
      return (await _clients.clientById(visit.clientId))?.name;
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
      return null;
    }
  }

  /// Takes a photo for [slot] of the zone with [zoneId], keeps its file, and saves the visit with it.
  ///
  /// A photo that the slot already holds is replaced, and its file is deleted after storage took the new photo.
  /// The photos of the visit stay as they were when the person closes the camera without a photo, and when the
  /// camera, the photo store, or storage fails. The camera does not open when storage does not take the capture that
  /// it opens for. A call does nothing while the visit takes no change.
  Future<void> capturePhoto(String zoneId, PhotoSlot slot, {PhotoSource source = PhotoSource.camera}) async {
    final visit = state.visit;
    final record = visit?.recordFor(zoneId);
    if (visit == null || record == null || !state.status.takesChange) return;
    emit(state.copyWith(status: VisitCaptureStatus.capturing));
    // The visit takes no note while a capture runs, so the newest save tells whether storage holds the notes of the
    // state. A note that was on its way when the capture started reports its answer here.
    final areNotesStored = await _newestSave;
    VisitCaptureState after(VisitCaptureStatus status) =>
        state.copyWith(status: status, isStored: areNotesStored, isSavingNote: false);

    if (!await _storeOpenCapture(OpenCapture(visitId: visit.id, zoneId: zoneId, slot: slot, source: source))) {
      _show(after(VisitCaptureStatus.saveFailed));
      return;
    }

    final PhotoRef photo;
    final DateTime? capturedAt;
    String? temporaryCameraPhoto;
    try {
      final picked = await _takePhoto(source);
      if (picked == null) {
        _show(after(VisitCaptureStatus.ready));
        return;
      }
      capturedAt = picked.capturedAt;
      if (source == PhotoSource.camera && _photoCapture is OwnedCameraPhotoCapture) {
        temporaryCameraPhoto = picked.path;
      }
      photo = await _photoStore.save(sourcePath: picked.path, visitId: visit.id, photoId: _idGenerator.newId());
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
      final isDenied = error is PhotoCaptureException && error.isAccessDenied;
      _show(after(isDenied ? VisitCaptureStatus.captureDenied : VisitCaptureStatus.captureFailed));
      return;
    } finally {
      // The store has finished copying (or failed); only this camera's owned source may now be released.
      if (temporaryCameraPhoto case final path?) await _discardCameraPhoto(path);
    }

    final changed = visit.withRecord(record.withPhoto(slot, photo, source: source, capturedAt: capturedAt));
    if (await _save(changed)) {
      _show(state.copyWith(status: VisitCaptureStatus.ready, visit: changed, isStored: true, isSavingNote: false));
      // The old file goes only now, so that a failed save leaves the slot with the photo that storage names.
      if (record.photoIn(slot) case final replaced?) await _deleteFile(replaced);
    } else {
      // The state does not take the photo, so storage and the state differ only in what they differed before.
      _newestSave = Future.value(areNotesStored);
      _show(after(VisitCaptureStatus.saveFailed));
      await _deleteFile(photo);
    }
  }

  Future<void> _discardCameraPhoto(String path) async {
    try {
      await (_photoCapture as OwnedCameraPhotoCapture).discardCameraPhoto(path);
    } on Object catch (error, stackTrace) {
      // Cache cleanup never replaces the photo/save outcome or touches borrowed gallery/report files.
      _report(error, stackTrace);
    }
  }

  /// Prepares the external picker intent before capture, and completes with true when storage took the change.
  ///
  /// The system can end the app while the camera app is open, and the next start of the app then reads the stored
  /// capture to put the photo into its slot. Storage can still hold the capture of an earlier camera whose photo did
  /// not come, so the camera must not open while storage names another capture: a lost photo would go to that one.
  Future<bool> _storeOpenCapture(OpenCapture capture) async {
    try {
      // An in-app camera has no external picker answer to recover. Clear an older intent so that a stale picker
      // result cannot be attached to this session after process death. Gallery still needs its external intent.
      if (_photoCapture is InAppPhotoCapture && capture.source == PhotoSource.camera) {
        await _openCaptures.clear();
      } else {
        await _openCaptures.save(capture);
      }
      return true;
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
      return false;
    }
  }

  /// Opens the camera, and removes the stored capture when the camera answers in any way.
  ///
  /// A failed removal is reported and does not change the answer: the camera gave its answer to this call, so the
  /// next start finds no photo for the capture, and the next capture replaces it.
  Future<({String path, DateTime? capturedAt})?> _takePhoto(PhotoSource source) async {
    try {
      if (_photoCapture case final InAppPhotoCapture capture when source == PhotoSource.camera) {
        final observed = await capture.takeObservedPhoto();
        return observed == null ? null : (path: observed.path, capturedAt: observed.capturedAt);
      }
      final path = source == PhotoSource.gallery
          ? await _photoCapture.selectGalleryPhoto()
          : await _photoCapture.takePhoto();
      return path == null ? null : (path: path, capturedAt: null);
    } finally {
      try {
        await _openCaptures.clear();
      } on Exception catch (error, stackTrace) {
        _report(error, stackTrace);
      }
    }
  }

  /// Sets the note of the zone with [zoneId] to [note], shows it at once, and saves the visit.
  ///
  /// The state keeps the note when storage does not take it, so that the person loses no text.
  /// [VisitCaptureState.isStored] then is false until a later save holds the note, and
  /// [VisitCaptureState.isSavingNote] is true until storage answers. A call does nothing while the visit takes no
  /// change.
  Future<void> editNote(String zoneId, String note) async {
    final visit = state.visit;
    final record = visit?.recordFor(zoneId);
    if (visit == null || record == null || !state.status.takesChange || record.note == note) return;
    await _saveEntry(visit.withRecord(record.withNote(note)));
  }

  /// Sets the status of the zone with [zoneId] to [status], shows it at once, and saves the visit, as [editNote] does
  /// with a note. The record keeps its reason when [status] is done, so that a status that was set by mistake and then
  /// set back loses no text.
  Future<void> setStatus(String zoneId, ZoneStatus status) async {
    final visit = state.visit;
    final record = visit?.recordFor(zoneId);
    if (visit == null || record == null || !state.status.takesChange || record.status == status) return;
    await _saveEntry(visit.withRecord(record.withStatus(status)));
  }

  /// Sets the reason of the zone with [zoneId] to [reason], shows it at once, and saves the visit, as [editNote] does
  /// with a note.
  Future<void> editReason(String zoneId, String reason) async {
    final visit = state.visit;
    final record = visit?.recordFor(zoneId);
    if (visit == null || record == null || !state.status.takesChange || record.reason == reason) return;
    await _saveEntry(visit.withRecord(record.withReason(reason)));
  }

  /// Shows [changed], which differs from the visit of the state by one entry of the person, and saves it.
  Future<void> _saveEntry(Visit changed) async {
    emit(state.copyWith(visit: changed, isSavingNote: true));
    await _saveNotes(changed);
  }

  /// Sends the visit to storage again, after storage did not take a note, a status, or a reason.
  ///
  /// A call does nothing while storage holds every entry and while the visit takes no change.
  Future<void> saveAgain() async {
    final visit = state.visit;
    if (visit == null || !state.status.takesChange || state.isStored) return;
    emit(state.copyWith(isSavingNote: true));
    await _saveNotes(visit);
  }

  /// Saves [visit], which differs from the visit in storage by its notes, statuses, or reasons, and reports the answer
  /// in [VisitCaptureState.isStored].
  Future<void> _saveNotes(Visit visit) async {
    final save = _save(visit);
    final isSaved = await save;
    // A capture that started after this save waits for it and reports its answer.
    if (isClosed || state.status == VisitCaptureStatus.capturing) return;
    final isNewest = identical(save, _newestSave);
    if (!isSaved) {
      // A newer save is still on its way when this one is not the newest.
      emit(state.copyWith(isStored: false, isSavingNote: isNewest ? false : null));
    } else if (isNewest) {
      // An older save that storage took says nothing about the notes that came after it.
      emit(state.copyWith(isStored: true, isSavingNote: false));
    }
  }

  /// Sends [visit] to storage now, and completes with true when storage took it.
  ///
  /// The repository has the visit before this method returns, so a save needs nothing more from the cubit, and a
  /// person who leaves the screen loses no change.
  Future<bool> _save(Visit visit) => _newestSave = _send(visit);

  Future<bool> _send(Visit visit) async {
    try {
      await _visits.save(visit);
      return true;
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
      return false;
    }
  }

  /// Deletes the file of [photo], which no record names. A file that stays takes space and breaks nothing.
  Future<void> _deleteFile(PhotoRef photo) async {
    try {
      await _photoStore.delete(photo);
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  void _show(VisitCaptureState next) {
    if (!isClosed) emit(next);
  }

  void _report(Object error, StackTrace stackTrace) {
    if (!isClosed) addError(error, stackTrace);
  }
}
