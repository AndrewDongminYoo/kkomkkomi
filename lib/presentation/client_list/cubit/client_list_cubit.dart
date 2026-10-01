import 'package:bloc/bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';

part 'client_list_state.dart';

/// Loads the active clients and adds a client.
class ClientListCubit extends Cubit<ClientListState> {
  new({
    required this._clients,
    required this._idGenerator,
    required this._clock,
  }) : super(const ClientListState());

  final ClientRepository _clients;
  final IdGenerator _idGenerator;
  final Clock _clock;

  /// Reads the active clients from storage.
  ///
  /// The list that the state holds stays in place while storage answers, so a second call does not hide it.
  Future<void> load() async {
    if (state.status == ClientListStatus.loadFailed) emit(state.copyWith(status: ClientListStatus.loading));
    try {
      final clients = await _clients.activeClients();
      if (isClosed) return;
      emit(state.copyWith(status: ClientListStatus.ready, clients: clients));
    } on Exception catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: ClientListStatus.loadFailed));
    }
  }

  /// Forgets what became of the last submitted name, before the dialog for a new client opens.
  void startNameEntry() => emit(state.copyWith(entry: NameEntry.editing));

  /// Saves a new client with [name] and puts it at the end of the list.
  ///
  /// [ClientListState.entry] tells what became of [name]. A call while a name is on its way to storage does nothing.
  Future<void> addClient(String name) async {
    if (state.entry == NameEntry.saving) return;
    final Client client;
    try {
      client = Client(id: _idGenerator.newId(), name: name, createdAt: _clock.now());
    } on DomainException catch (exception) {
      emit(state.copyWith(entry: NameEntry.refusedBy(exception)));
      return;
    }
    emit(state.copyWith(entry: NameEntry.saving));
    try {
      await _clients.save(client);
      if (isClosed) return;
      emit(state.copyWith(clients: [...state.clients, client], entry: NameEntry.saved));
    } on Exception catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(entry: NameEntry.failed));
    }
  }
}
