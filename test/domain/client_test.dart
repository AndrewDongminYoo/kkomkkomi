// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  final createdAt = DateTime.utc(2026, 10, 1, 9);

  Client client({String name = '한빛 사무실', bool isArchived = false}) =>
      Client(id: 'client-1', name: name, createdAt: createdAt, isArchived: isArchived);

  group('Client', () {
    test('trims the name', () {
      expect(client(name: '  한빛 사무실 ').name, '한빛 사무실');
    });

    test('refuses a name that is empty after trimming', () {
      expect(() => client(name: ''), throwsA(isA<EmptyNameException>()));
      expect(() => client(name: ' \t\n'), throwsA(isA<EmptyNameException>()));
    });

    test('is not archived unless told so', () {
      expect(client().isArchived, isFalse);
    });

    test('keeps the creation time as the same moment in UTC', () {
      final local = DateTime(2026, 10, 1, 9, 30);

      final created = Client(id: 'client-1', name: '한빛 사무실', createdAt: local).createdAt;

      expect(created.isUtc, isTrue);
      expect(created.isAtSameMomentAs(local), isTrue);
    });

    test('rename trims the new name and keeps the other fields', () {
      expect(client(isArchived: true).rename(' 새 이름 '), client(name: '새 이름', isArchived: true));
    });

    test('rename refuses an empty name', () {
      expect(() => client().rename('  '), throwsA(isA<EmptyNameException>()));
    });

    test('archive marks the client as archived and keeps the other fields', () {
      expect(client().archive(), client(isArchived: true));
    });

    test('is equal to a client with the same fields', () {
      expect(client(), client());
      expect(client().hashCode, client().hashCode);
    });

    test('differs from a client with another field value', () {
      expect(client(), isNot(client(name: '다른 이름')));
      expect(client(), isNot(client(isArchived: true)));
      expect(client(), isNot(Client(id: 'client-2', name: '한빛 사무실', createdAt: createdAt)));
      expect(client(), isNot(Client(id: 'client-1', name: '한빛 사무실', createdAt: DateTime.utc(2026, 10, 2))));
    });
  });
}
