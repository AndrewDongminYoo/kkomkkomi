// Every field of the class is final, and `package:meta`, which has `@immutable`, is not a dependency.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

part of 'client_detail_cubit.dart';

enum ClientDetailStatus {
  /// The client is on its way from storage.
  loading,

  /// Storage did not give the client.
  loadFailed,

  /// The state holds what storage has.
  ready,

  /// The state holds a change that is on its way to storage.
  saving,

  /// Storage did not take the last change, and the state holds what it held before that change.
  saveFailed,

  /// The client is archived, so the screen has nothing more to show.
  archived,

  /// Storage took a new visit, which [ClientDetailState.startedVisitId] names, and the state holds what storage has.
  visitStarted,
}

final class ClientDetailState {
  const new({
    this.status = ClientDetailStatus.loading,
    this.client,
    this.zones,
    this.visits = const [],
    this.entry = NameEntry.editing,
    this.startedVisitId,
  });

  final ClientDetailStatus status;

  /// The client, or null while it is not loaded.
  final Client? client;

  /// The zones of the client, removed zones included, or null while they are not loaded.
  final ClientZones? zones;

  /// The visits of the client, newest first.
  final List<Visit> visits;

  /// What became of the name that a name dialog of the screen last submitted.
  final NameEntry entry;

  /// The visit that the screen last started, or null when it started none.
  final String? startedVisitId;

  /// The zones that the screen lists, in position order.
  List<Zone> get activeZones => zones?.active ?? const [];

  /// Whether a person can change the client, its zones, and its visits in this status.
  bool get takesChange =>
      status == ClientDetailStatus.ready ||
      status == ClientDetailStatus.saveFailed ||
      status == ClientDetailStatus.visitStarted;

  ClientDetailState copyWith({
    ClientDetailStatus? status,
    Client? client,
    ClientZones? zones,
    List<Visit>? visits,
    NameEntry? entry,
    String? startedVisitId,
  }) => ClientDetailState(
    status: status ?? this.status,
    client: client ?? this.client,
    zones: zones ?? this.zones,
    visits: visits ?? this.visits,
    entry: entry ?? this.entry,
    startedVisitId: startedVisitId ?? this.startedVisitId,
  );

  @override
  bool operator ==(Object other) =>
      other is ClientDetailState &&
      other.status == status &&
      other.client == client &&
      other.zones == zones &&
      other.entry == entry &&
      other.startedVisitId == startedVisitId &&
      sameElements(other.visits, visits);

  @override
  int get hashCode => Object.hash(status, client, zones, entry, startedVisitId, Object.hashAll(visits));
}
