import 'package:bloc/bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

part 'visit_capture_state.dart';

/// Loads one visit, and saves each photo and each note of its zone records at once.
///
/// Every save holds the whole visit. A note edit goes to the repository at the moment of the edit, without a wait
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
  Future<void> capturePhoto(String zoneId, PhotoSlot slot) async {
    final visit = state.visit;
    final record = visit?.recordFor(zoneId);
    if (visit == null || record == null || !state.status.takesChange) return;
    emit(state.copyWith(status: VisitCaptureStatus.capturing));
    // The visit takes no note while a capture runs, so the newest save tells whether storage holds the notes of the
    // state. A note that was on its way when the capture started reports its answer here.
    final areNotesStored = await _newestSave;
    VisitCaptureState after(VisitCaptureStatus status) =>
        state.copyWith(status: status, isStored: areNotesStored, isSavingNote: false);

    if (!await _storeOpenCapture(OpenCapture(visitId: visit.id, zoneId: zoneId, slot: slot))) {
      _show(after(VisitCaptureStatus.saveFailed));
      return;
    }

    final PhotoRef photo;
    try {
      final picked = await _takePhoto();
      if (picked == null) {
        _show(after(VisitCaptureStatus.ready));
        return;
      }
      photo = await _photoStore.save(sourcePath: picked, visitId: visit.id, photoId: _idGenerator.newId());
    } on Exception catch (error, stackTrace) {
      _report(error, stackTrace);
      final isDenied = error is PhotoCaptureException && error.isAccessDenied;
      _show(after(isDenied ? VisitCaptureStatus.captureDenied : VisitCaptureStatus.captureFailed));
      return;
    }

    final changed = visit.withRecord(record.withPhoto(slot, photo));
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

  /// Stores [capture] before the camera opens, and completes with true when storage took it.
  ///
  /// The system can end the app while the camera app is open, and the next start of the app then reads the stored
  /// capture to put the photo into its slot. Storage can still hold the capture of an earlier camera whose photo did
  /// not come, so the camera must not open while storage names another capture: a lost photo would go to that one.
  Future<bool> _storeOpenCapture(OpenCapture capture) async {
    try {
      await _openCaptures.save(capture);
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
  Future<String?> _takePhoto() async {
    try {
      return await _photoCapture.takePhoto();
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
    final changed = visit.withRecord(record.withNote(note));
    emit(state.copyWith(visit: changed, isSavingNote: true));
    await _saveNotes(changed);
  }

  /// Sends the visit to storage again, after storage did not take a note.
  ///
  /// A call does nothing while storage holds the notes and while the visit takes no change.
  Future<void> saveAgain() async {
    final visit = state.visit;
    if (visit == null || !state.status.takesChange || state.isStored) return;
    emit(state.copyWith(isSavingNote: true));
    await _saveNotes(visit);
  }

  /// Saves [visit], which differs from the visit in storage by its notes, and reports the answer in
  /// [VisitCaptureState.isStored].
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
