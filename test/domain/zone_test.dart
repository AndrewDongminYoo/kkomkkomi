import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  Zone zone({String id = 'zone-1', String name = '로비', int position = 0, bool isActive = true}) =>
      Zone(id: id, clientId: 'client-1', name: name, position: position, isActive: isActive);

  group('Zone', () {
    test('trims the name', () {
      expect(zone(name: ' 로비  ').name, '로비');
    });

    test('refuses a name that is empty after trimming', () {
      expect(() => zone(name: '   '), throwsA(isA<EmptyNameException>()));
    });

    test('is active unless told so', () {
      expect(Zone(id: 'zone-1', clientId: 'client-1', name: '로비', position: 0).isActive, isTrue);
    });

    test('rename trims the new name and keeps the other fields', () {
      expect(zone(position: 3, isActive: false).rename(' 회의실 '), zone(name: '회의실', position: 3, isActive: false));
    });

    test('rename refuses an empty name', () {
      expect(() => zone().rename(''), throwsA(isA<EmptyNameException>()));
    });

    test('deactivate keeps every field but isActive', () {
      expect(zone(position: 2).deactivate(), zone(position: 2, isActive: false));
    });

    test('is equal to a zone with the same fields', () {
      expect(zone(), zone());
      expect(zone().hashCode, zone().hashCode);
    });

    test('differs from a zone with another field value', () {
      expect(zone(), isNot(zone(id: 'zone-2')));
      expect(zone(), isNot(zone(name: '회의실')));
      expect(zone(), isNot(zone(position: 1)));
      expect(zone(), isNot(zone(isActive: false)));
      expect(zone(), isNot(Zone(id: 'zone-1', clientId: 'client-2', name: '로비', position: 0)));
    });
  });
}
