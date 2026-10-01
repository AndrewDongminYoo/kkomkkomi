// `lib/application/` imports only the domain, so `@immutable` from `package:meta` is not available here. Every
// field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'dart:math';

/// The fixed web page of one client, under which every published visit of that client is a report.
///
/// [id] is the client's fixed URL, so it is hard to guess: [newPageId] makes it. A revoked page stays revoked, and a
/// reissue gives the client a new page.
final class ClientPage {
  new({required this.id, required this.clientId, required DateTime createdAt, DateTime? revokedAt})
    : createdAt = createdAt.toUtc(),
      revokedAt = revokedAt?.toUtc();

  final String id;
  final String clientId;

  /// The creation time in UTC. The published page holds the same time, so a repeated write does not change it.
  final DateTime createdAt;

  /// The time of the access removal in UTC, or null while the page is open.
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;

  ClientPage revoke(DateTime at) => ClientPage(id: id, clientId: clientId, createdAt: createdAt, revokedAt: at);

  @override
  bool operator ==(Object other) =>
      other is ClientPage &&
      other.id == id &&
      other.clientId == clientId &&
      other.createdAt == createdAt &&
      other.revokedAt == revokedAt;

  @override
  int get hashCode => Object.hash(id, clientId, createdAt, revokedAt);

  @override
  String toString() => 'ClientPage($id, $clientId, $createdAt, $revokedAt)';
}

/// The number of random bits in the ID of a client page.
const pageIdBits = 128;

/// A new page ID of [pageIdBits] bits from [random], written as hexadecimal digits.
///
/// The page ID does not come from the `IdGenerator` port, because the port does not promise random bits, and the
/// ID of a page is the only thing that keeps a report link hard to guess.
String newPageId(Random random) =>
    [for (var byte = 0; byte < pageIdBits ~/ 8; byte++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
