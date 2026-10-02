import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  const lobbyBefore = OpenCapture(visitId: 'visit-1', zoneId: 'zone-1', slot: PhotoSlot.before);

  group('OpenCapture', () {
    test('is equal to a capture with the same visit, zone, and slot', () {
      expect(lobbyBefore, const OpenCapture(visitId: 'visit-1', zoneId: 'zone-1', slot: PhotoSlot.before));
      expect(
        lobbyBefore.hashCode,
        const OpenCapture(visitId: 'visit-1', zoneId: 'zone-1', slot: PhotoSlot.before).hashCode,
      );
    });

    test('differs from a capture with another visit, zone, or slot', () {
      expect(lobbyBefore, isNot(const OpenCapture(visitId: 'visit-9', zoneId: 'zone-1', slot: PhotoSlot.before)));
      expect(lobbyBefore, isNot(const OpenCapture(visitId: 'visit-1', zoneId: 'zone-9', slot: PhotoSlot.before)));
      expect(lobbyBefore, isNot(const OpenCapture(visitId: 'visit-1', zoneId: 'zone-1', slot: PhotoSlot.after)));
    });

    test('names its visit, zone, and slot in its description', () {
      expect(lobbyBefore.toString(), 'OpenCapture(visit-1, zone-1, before)');
    });
  });
}
