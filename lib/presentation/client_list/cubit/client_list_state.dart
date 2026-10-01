// Every field of the class is final, and `package:meta`, which has `@immutable`, is not a dependency.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

part of 'client_list_cubit.dart';

enum ClientListStatus {
  /// The clients are on their way from storage.
  loading,

  /// Storage did not give the clients.
  loadFailed,

  /// [ClientListState.clients] holds what storage has.
  ready,
}

final class ClientListState {
  const new({this.status = ClientListStatus.loading, this.clients = const [], this.entry = NameEntry.editing});

  final ClientListStatus status;

  /// The clients that are not archived, oldest first.
  final List<Client> clients;

  /// What became of the name that the dialog for a new client last submitted.
  final NameEntry entry;

  ClientListState copyWith({ClientListStatus? status, List<Client>? clients, NameEntry? entry}) => ClientListState(
    status: status ?? this.status,
    clients: clients ?? this.clients,
    entry: entry ?? this.entry,
  );

  @override
  bool operator ==(Object other) =>
      other is ClientListState &&
      other.status == status &&
      other.entry == entry &&
      sameElements(other.clients, clients);

  @override
  int get hashCode => Object.hash(status, entry, Object.hashAll(clients));
}
