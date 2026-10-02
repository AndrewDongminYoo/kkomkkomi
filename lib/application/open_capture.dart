// `lib/application/` imports only the domain, so `@immutable` from `package:meta` is not available here. Every
// field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:kkomkkomi/domain/domain.dart';

/// The capture that has the camera open: the visit, the zone, and the slot that its photo is for.
///
/// The app stores it before the camera opens and removes it when the capture ends. When the system ends the app
/// while the camera app is open, the stored capture tells the next start where the photo of that capture belongs.
final class OpenCapture {
  const new({required this.visitId, required this.zoneId, required this.slot});

  final String visitId;
  final String zoneId;
  final PhotoSlot slot;

  @override
  bool operator ==(Object other) =>
      other is OpenCapture && other.visitId == visitId && other.zoneId == zoneId && other.slot == slot;

  @override
  int get hashCode => Object.hash(visitId, zoneId, slot);

  @override
  String toString() => 'OpenCapture($visitId, $zoneId, ${slot.name})';
}

/// Stores the one [OpenCapture] of the app, so that it outlives the end of the app.
abstract interface class OpenCaptureRepository {
  /// The stored capture, or null when none is stored.
  Future<OpenCapture?> load();

  /// Stores [capture] in place of the stored one.
  Future<void> save(OpenCapture capture);

  /// Removes the stored capture. Removing when none is stored is no failure.
  Future<void> clear();
}
