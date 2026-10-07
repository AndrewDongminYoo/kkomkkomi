// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';

void main() {
  final at = DateTime.parse('2026-10-03T10:00:00.123456+09:00');
  final utc = DateTime.utc(2026, 10, 3, 1, 0, 0, 123, 456);
  final later = utc.add(const Duration(minutes: 1));

  ClientPage page({DateTime? revokedAt, DateTime? requestedAt, DateTime? deletedAt}) => ClientPage(
    id: 'page-1',
    clientId: 'client-1',
    createdAt: at,
    revokedAt: revokedAt,
    serverDeleteRequestedAt: requestedAt,
    serverDeletedAt: deletedAt,
  );

  group('ClientPage deletion state', () {
    test('normalizes deletion times and preserves them through revoke', () {
      final stored = page(requestedAt: at, deletedAt: at).revoke(later);
      expect(stored.createdAt, utc);
      expect(stored.serverDeleteRequestedAt, utc);
      expect(stored.serverDeletedAt, utc);
      expect(stored.revokedAt, later);
      expect(stored.isRevoked, isTrue);
    });

    test('keeps the first intent and confirmation', () {
      final requested = page().requestServerDeletion(at);
      expect(requested.serverDeleteRequestedAt, utc);
      expect(requested.serverDeletedAt, isNull);
      expect(requested.isServerDeletionPending, isTrue);
      expect(requested.requestServerDeletion(later), requested);
      final confirmed = requested.confirmServerDeletion(at);
      expect(confirmed.serverDeletedAt, utc);
      expect(confirmed.isServerDeletionPending, isFalse);
      expect(confirmed.requestServerDeletion(later).confirmServerDeletion(later), confirmed);
    });

    test('quarantines confirmed pages without intent', () {
      final confirmed = page().confirmServerDeletion(at);
      expect(confirmed.serverDeleteRequestedAt, isNull);
      expect(confirmed.serverDeletedAt, utc);
      expect(confirmed.isQuarantined, isTrue);
      expect(confirmed.isServerDeletionPending, isFalse);
      expect(confirmed.isOpen, isFalse);
    });

    test('selects only pages with no revoke, intent, or confirmation as open', () {
      expect(page().isOpen, isTrue);
      expect(page().isQuarantined, isFalse);
      expect(page(revokedAt: at).isOpen, isFalse);
      expect(page(requestedAt: at).isOpen, isFalse);
      expect(page(deletedAt: at).isOpen, isFalse);
      expect(page(revokedAt: at, requestedAt: at).isServerDeletionPending, isTrue);
    });

    test('distinguishes pages with different persisted deletion state', () {
      final plain = page();
      final requested = page(requestedAt: at);
      final confirmed = page(requestedAt: at, deletedAt: at);
      expect(requested, page(requestedAt: utc));
      expect(requested.hashCode, page(requestedAt: utc).hashCode);
      expect({plain, requested, confirmed}, hasLength(3));
      expect(confirmed.toString(), contains('$utc, $utc'));
    });
  });
}
