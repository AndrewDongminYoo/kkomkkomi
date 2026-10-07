// `lib/application/` imports only the domain, so `@immutable` from `package:meta` is not available here. Every
// field of each class is final.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'dart:typed_data';

import 'package:kkomkkomi/domain/domain.dart';

/// Writes published reports to the backend, so that tests never reach one.
///
/// Each call is safe to repeat: a repeated call leaves the backend as the first call left it. A call that fails
/// throws a [PublishException]. The queue asks the identity for the user ID before it calls a method, so an adapter
/// can rely on a signed-in user.
abstract interface class Publisher {
  /// Whether the flavor has a backend. The queue stops every job of a flavor without one.
  bool get isAvailable;

  /// Writes the client page with [pageId].
  Future<void> writePage(String pageId, PublishedPage page);

  /// Uploads [bytes] as a JPEG to [objectPath].
  ///
  /// When [cancel] completes, the adapter asks the backend to stop the upload. The call then ends as the upload
  /// ends: with a [PublishException] when the upload stopped, and without one when the object arrived anyway.
  Future<void> uploadPhoto(String objectPath, Uint8List bytes, {required Future<void> cancel});

  /// Writes the report of the visit with [visitId] under the client page with [pageId].
  Future<void> writeReport({required String pageId, required String visitId, required PublishedReport report});

  /// Writes the client page with [pageId] as [page], revoked at [revokedAt].
  ///
  /// A page that the backend does not hold yet is written revoked, so the call does not depend on an earlier
  /// [writePage] that may not have reached the backend. The caller gives the time, so a repeated call writes the same
  /// page.
  Future<void> revokePage(String pageId, PublishedPage page, {required DateTime revokedAt});

  /// Deletes the object at [objectPath]. An object that does not exist is no failure.
  Future<void> deletePhoto(String objectPath);

  /// Deletes the report of the visit with [visitId] under the client page with [pageId]. A report that does not exist
  /// is no failure.
  Future<void> deleteReport({required String pageId, required String visitId});

  /// Deletes the client page with [pageId]. A page that does not exist is no failure. The reports of the page are
  /// separate documents, which [deleteReport] deletes.
  Future<void> deletePage(String pageId);
}

/// Whether a retry can fix a failed call of a [Publisher].
enum PublishErrorKind {
  /// A retry can fix it, for example a missing network.
  transient,

  /// A retry cannot fix it, for example a write that the rules of the backend refuse.
  refused,
}

/// A call of a [Publisher] failed.
final class PublishException implements Exception {
  const new(this.kind, this.message);

  final PublishErrorKind kind;

  /// What the backend said, for the log.
  final String message;

  @override
  String toString() => 'PublishException(${kind.name}, $message)';
}

/// What a client page shows above its reports.
final class PublishedPage {
  new({required this.ownerUid, required this.companyName, required this.clientName, required DateTime createdAt})
    : createdAt = createdAt.toUtc();

  /// The user who may write the page, its reports, and its photos.
  final String ownerUid;

  /// The name of the cleaning company, or null when no company profile is saved.
  final String? companyName;
  final String clientName;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is PublishedPage &&
      other.ownerUid == ownerUid &&
      other.companyName == companyName &&
      other.clientName == clientName &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(ownerUid, companyName, clientName, createdAt);

  @override
  String toString() => 'PublishedPage($ownerUid, $companyName, $clientName, $createdAt)';
}

/// What the report of one visit shows.
final class PublishedReport {
  new({
    required this.visitDate,
    required DateTime publishedAt,
    required Iterable<PublishedZone> zones,
    this.unbranded = false,
  }) : publishedAt = publishedAt.toUtc(),
       zones = List.unmodifiable(zones);

  final VisitDate visitDate;

  /// The time of the publish request in UTC, which stays the same when a job writes the report again.
  final DateTime publishedAt;

  /// The zones in the order of the visit.
  final List<PublishedZone> zones;

  /// Whether the report shows without the footer, which the rules accept only from a writer with a paid entitlement.
  final bool unbranded;

  @override
  bool operator ==(Object other) =>
      other is PublishedReport &&
      other.visitDate == visitDate &&
      other.publishedAt == publishedAt &&
      sameElements(other.zones, zones) &&
      other.unbranded == unbranded;

  @override
  int get hashCode => Object.hash(visitDate, publishedAt, Object.hashAll(zones), unbranded);

  @override
  String toString() => 'PublishedReport($visitDate, $publishedAt, $zones, unbranded: $unbranded)';
}

/// What a report shows for one zone. A photo is the path of its object, never a download URL.
final class PublishedZone {
  const new({
    required this.name,
    required this.note,
    required this.beforePhoto,
    required this.afterPhoto,
    this.beforePhotoSource = PhotoSource.unknown,
    this.afterPhotoSource = PhotoSource.unknown,
    this.status = ZoneStatus.done,
    this.reason = '',
  });

  final String name;
  final String note;
  final String? beforePhoto;
  final String? afterPhoto;
  final PhotoSource beforePhotoSource;
  final PhotoSource afterPhotoSource;

  /// Whether the visit cleaned the zone as agreed.
  final ZoneStatus status;

  /// What is left or why, for an exception, or an empty text.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is PublishedZone &&
      other.name == name &&
      other.note == note &&
      other.beforePhoto == beforePhoto &&
      other.afterPhoto == afterPhoto &&
      other.beforePhotoSource == beforePhotoSource &&
      other.afterPhotoSource == afterPhotoSource &&
      other.status == status &&
      other.reason == reason;

  @override
  int get hashCode =>
      Object.hash(name, note, beforePhoto, afterPhoto, beforePhotoSource, afterPhotoSource, status, reason);

  @override
  String toString() => 'PublishedZone($name, $note, $beforePhoto, $afterPhoto, ${status.name}, $reason)';
}
