// Every field of the class is final, and `package:meta`, which has `@immutable`, is not a dependency.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

part of 'visit_capture_cubit.dart';

enum VisitCaptureStatus {
  /// The visit is on its way from storage.
  loading,

  /// Storage did not give the visit.
  loadFailed,

  /// The state holds the visit, and the last capture changed it or the person closed the camera.
  ready,

  /// The camera is open, or the new photo is on its way to storage. The visit takes no other change.
  capturing,

  /// The camera or the photo store gave no photo, and the photos are as they were before the capture.
  captureFailed,

  /// The person did not allow the app to use the camera, and the photos are as they were before the capture.
  captureDenied,

  /// Storage did not take the new photo, and the photos are as they were before the capture.
  saveFailed;

  /// Whether a person can change the visit in this status.
  bool get takesChange => switch (this) {
    ready || captureFailed || captureDenied || saveFailed => true,
    loading || loadFailed || capturing => false,
  };
}

final class VisitCaptureState {
  const new({
    this.status = VisitCaptureStatus.loading,
    this.visit,
    this.clientName,
    this.previousPhotos = const {},
    this.photoDirectory = '',
    this.isStored = true,
    this.isSavingNote = false,
  });

  final VisitCaptureStatus status;

  /// The visit, or null while it is not loaded.
  final Visit? visit;

  /// The name of the client of [visit], or null while the visit is not loaded or storage did not give the client.
  final String? clientName;

  /// The previous photos of each zone of the visit, by zone identifier. A zone without an earlier record has no entry.
  final Map<String, PreviousPhotos> previousPhotos;

  /// The absolute path of the directory that the path of each photo is relative to, in this launch of the app.
  final String photoDirectory;

  /// Whether storage holds every note, status, and reason of [visit], as far as the answers to the saves tell.
  ///
  /// It is false after storage did not take one of them, until a later save holds it. The photos of [visit] are
  /// always in storage, because the state takes a photo only after storage took it.
  final bool isStored;

  /// Whether a note, a status, or a reason is on its way to storage and the answer to the newest save is not here.
  final bool isSavingNote;

  /// Whether the person can leave the screen and lose nothing: storage holds every entry, and none is on its way.
  bool get canLeave => isStored && !isSavingNote;

  /// The absolute path of the file of [photo] in this launch of the app.
  String pathOf(PhotoRef photo) => '$photoDirectory/${photo.path}';

  VisitCaptureState copyWith({VisitCaptureStatus? status, Visit? visit, bool? isStored, bool? isSavingNote}) =>
      VisitCaptureState(
        status: status ?? this.status,
        visit: visit ?? this.visit,
        clientName: clientName,
        previousPhotos: previousPhotos,
        photoDirectory: photoDirectory,
        isStored: isStored ?? this.isStored,
        isSavingNote: isSavingNote ?? this.isSavingNote,
      );

  @override
  bool operator ==(Object other) =>
      other is VisitCaptureState &&
      other.status == status &&
      other.visit == visit &&
      other.clientName == clientName &&
      other.photoDirectory == photoDirectory &&
      other.isStored == isStored &&
      other.isSavingNote == isSavingNote &&
      sameEntries(other.previousPhotos, previousPhotos);

  @override
  int get hashCode => Object.hash(
    status,
    visit,
    clientName,
    photoDirectory,
    isStored,
    isSavingNote,
    Object.hashAllUnordered([for (final entry in previousPhotos.entries) Object.hash(entry.key, entry.value)]),
  );
}
