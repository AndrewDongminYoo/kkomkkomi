part of 'still_camera_cubit.dart';

enum StillCameraStatus { loading, ready, capturing, suspended, complete }

final class StillCameraState {
  const new({this.status = StillCameraStatus.loading, this.photo, this.failure});
  final StillCameraStatus status;
  final ObservedCameraPhoto? photo;
  final PhotoCaptureException? failure;

  @override
  bool operator ==(Object other) =>
      other is StillCameraState && other.status == status && other.photo == photo && other.failure == failure;

  @override
  int get hashCode => Object.hash(status, photo, failure);
}
// Every field is final; this unit follows the existing hand-written state convention.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
