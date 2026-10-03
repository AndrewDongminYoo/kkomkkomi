// `lib/application/` imports only the domain, so `@immutable` from `package:meta` is not available here. Every
// field of the class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'dart:math';

/// The fixed web page of one client, under which every published visit of that client is a report.
///
/// [id] is the client's fixed URL, so it is hard to guess: [newPageId] makes it. A revoked page stays revoked, and a
/// reissue gives the client a new page.
final class ClientPage {
  new({
    required this.id,
    required this.clientId,
    required DateTime createdAt,
    DateTime? revokedAt,
    DateTime? serverDeleteRequestedAt,
    DateTime? serverDeletedAt,
  }) : createdAt = createdAt.toUtc(),
       revokedAt = revokedAt?.toUtc(),
       serverDeleteRequestedAt = serverDeleteRequestedAt?.toUtc(),
       serverDeletedAt = serverDeletedAt?.toUtc();

  final String id;
  final String clientId;

  /// The creation time in UTC. The published page holds the same time, so a repeated write does not change it.
  final DateTime createdAt;

  /// The local revoke request time in UTC, before its backend job completes.
  final DateTime? revokedAt;

  /// The first persisted intent to delete this server page, which does not prove remote success.
  final DateTime? serverDeleteRequestedAt;

  /// The first locally persisted backend deletion acknowledgement in UTC.
  final DateTime? serverDeletedAt;

  bool get isRevoked => revokedAt != null;
  bool get isQuarantined => serverDeleteRequestedAt != null || serverDeletedAt != null;
  bool get isServerDeletionPending => serverDeleteRequestedAt != null && serverDeletedAt == null;
  bool get isOpen => !isRevoked && !isQuarantined;

  ClientPage revoke(DateTime at) => _copyWith(revokedAt: at);

  ClientPage requestServerDeletion(DateTime at) => _copyWith(serverDeleteRequestedAt: serverDeleteRequestedAt ?? at);

  ClientPage confirmServerDeletion(DateTime at) => _copyWith(serverDeletedAt: serverDeletedAt ?? at);

  ClientPage _copyWith({DateTime? revokedAt, DateTime? serverDeleteRequestedAt, DateTime? serverDeletedAt}) =>
      ClientPage(
        id: id,
        clientId: clientId,
        createdAt: createdAt,
        revokedAt: revokedAt ?? this.revokedAt,
        serverDeleteRequestedAt: serverDeleteRequestedAt ?? this.serverDeleteRequestedAt,
        serverDeletedAt: serverDeletedAt ?? this.serverDeletedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is ClientPage &&
      other.id == id &&
      other.clientId == clientId &&
      other.createdAt == createdAt &&
      other.revokedAt == revokedAt &&
      other.serverDeleteRequestedAt == serverDeleteRequestedAt &&
      other.serverDeletedAt == serverDeletedAt;

  @override
  int get hashCode => Object.hash(id, clientId, createdAt, revokedAt, serverDeleteRequestedAt, serverDeletedAt);

  @override
  String toString() => 'ClientPage($id, $clientId, $createdAt, $revokedAt, $serverDeleteRequestedAt, $serverDeletedAt)';
}

/// The number of random bits in the ID of a client page.
const pageIdBits = 128;

/// A new page ID of [pageIdBits] bits from [random], written as hexadecimal digits.
///
/// The page ID does not come from the `IdGenerator` port, because the port does not promise random bits, and the
/// ID of a page is the only thing that keeps a report link hard to guess.
String newPageId(Random random) =>
    [for (var byte = 0; byte < pageIdBits ~/ 8; byte++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
