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

/// Where a press of the add control stands.
enum ClientAddition {
  /// No press waits for an answer.
  idle,

  /// The plan of the company is on its way. The add control takes no press.
  checking,

  /// The plan allows one more client, so the dialog for a new client opens.
  allowed,
}

final class ClientListState {
  const new({
    this.status = ClientListStatus.loading,
    this.clients = const [],
    this.entry = NameEntry.editing,
    this.addition = ClientAddition.idle,
    this.limitPlan,
  });

  final ClientListStatus status;

  /// The clients that are not archived, oldest first.
  final List<Client> clients;

  /// What became of the name that the dialog for a new client last submitted.
  final NameEntry entry;

  /// Where the last press of the add control stands.
  final ClientAddition addition;

  /// The plan whose client limit stopped the last addition, or null when none did since the list was last read.
  final Plan? limitPlan;

  ClientListState copyWith({
    ClientListStatus? status,
    List<Client>? clients,
    NameEntry? entry,
    ClientAddition? addition,
    Plan? Function()? limitPlan,
  }) => ClientListState(
    status: status ?? this.status,
    clients: clients ?? this.clients,
    entry: entry ?? this.entry,
    addition: addition ?? this.addition,
    limitPlan: limitPlan == null ? this.limitPlan : limitPlan(),
  );

  @override
  bool operator ==(Object other) =>
      other is ClientListState &&
      other.status == status &&
      other.entry == entry &&
      other.addition == addition &&
      other.limitPlan == limitPlan &&
      sameElements(other.clients, clients);

  @override
  int get hashCode => Object.hash(status, entry, addition, limitPlan, Object.hashAll(clients));
}
