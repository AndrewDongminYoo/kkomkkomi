// 📦 Package imports:
import 'package:bloc/bloc.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';

part 'client_detail_state.dart';

/// Loads one client with its zones and visits, saves each change to the client and to its zone list, and starts a
/// visit.
class ClientDetailCubit extends Cubit<ClientDetailState> {
  new({
    required this._clientId,
    required this._clients,
    required this._visits,
    required this._idGenerator,
    required this._startVisit,
  }) : super(const ClientDetailState());

  final String _clientId;
  final ClientRepository _clients;
  final VisitRepository _visits;
  final IdGenerator _idGenerator;
  final StartVisit _startVisit;

  /// Reads the client, its zones, and its visits from storage.
  ///
  /// A client that storage does not have is a failed load, because no client is ever deleted.
  Future<void> load() async {
    if (state.status != ClientDetailStatus.loading) emit(const ClientDetailState());
    try {
      final client = await _clients.clientById(_clientId);
      final zones = await _clients.zonesOf(_clientId);
      final visits = await _visits.visitsOf(_clientId);
      if (isClosed) return;
      emit(
        client == null
            ? const ClientDetailState(status: ClientDetailStatus.loadFailed)
            : ClientDetailState(status: ClientDetailStatus.ready, client: client, zones: zones, visits: visits),
      );
    } on Exception catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(const ClientDetailState(status: ClientDetailStatus.loadFailed));
    }
  }

  /// Forgets what became of the last submitted name, before a name dialog opens.
  void startNameEntry() => emit(state.copyWith(entry: NameEntry.editing));

  /// Renames the client. [ClientDetailState.entry] tells what became of [name].
  Future<void> renameClient(String name) => _save((client, zones) => (client.rename(name), zones), isNameEntry: true);

  /// Adds an active zone after every zone. [ClientDetailState.entry] tells what became of [name].
  Future<void> addZone(String name) =>
      _save((client, zones) => (client, zones.add(id: _idGenerator.newId(), name: name)), isNameEntry: true);

  /// Renames the zone with [zoneId]. [ClientDetailState.entry] tells what became of [name].
  Future<void> renameZone(String zoneId, String name) =>
      _save((client, zones) => (client, zones.rename(zoneId, name)), isNameEntry: true);

  /// Moves the zone at the index [from] of the listed zones to the index [to].
  Future<void> moveZone(int from, int to) => _save((client, zones) => (client, zones.move(from: from, to: to)));

  /// Takes the zone with [zoneId] out of the listed zones. Past visits keep their records of it.
  Future<void> removeZone(String zoneId) => _save((client, zones) => (client, zones.remove(zoneId)));

  /// Archives the client. The state ends with [ClientDetailStatus.archived] when storage takes the change.
  Future<void> archive() =>
      _save((client, zones) => (client.archive(), zones), statusAfter: ClientDetailStatus.archived);

  /// Starts a visit on [visitDate] from the listed zones and saves it.
  ///
  /// The state ends with [ClientDetailStatus.visitStarted], lists the visit, and names it in
  /// [ClientDetailState.startedVisitId] when storage takes it. A call does nothing while the client takes no change
  /// and while it lists no zone, because a visit keeps the zones that it started with.
  Future<void> startVisit(VisitDate visitDate) async {
    if (!state.takesChange || state.activeZones.isEmpty) return;
    emit(state.copyWith(status: ClientDetailStatus.saving));
    try {
      final visit = await _startVisit(clientId: _clientId, visitDate: visitDate);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: ClientDetailStatus.visitStarted,
          // The list keeps the order of the repository, newest first, without a second read that could fail after
          // the visit is saved.
          visits: [...state.visits, visit]..sort((a, b) => b.compareChronologically(a)),
          startedVisitId: visit.id,
        ),
      );
    } on Exception catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: ClientDetailStatus.saveFailed));
    }
  }

  /// Applies [change] to the client and its zones, shows the result at once, and saves it.
  ///
  /// The client and the zones go back to what they were when storage does not take the result. A name dialog reads
  /// the outcome from [ClientDetailState.entry] when [isNameEntry] is true, and the screen reads it from the status
  /// otherwise.
  /// A call does nothing while the client is not loaded, while another change is on its way to storage, and after
  /// the client is archived.
  Future<void> _save(
    (Client, ClientZones) Function(Client client, ClientZones zones) change, {
    bool isNameEntry = false,
    ClientDetailStatus statusAfter = ClientDetailStatus.ready,
  }) async {
    final before = state;
    final (client, zones) = (before.client, before.zones);
    if (client == null || zones == null || !before.takesChange) return;

    final (Client, ClientZones) changed;
    try {
      changed = change(client, zones);
    } on DomainException catch (exception) {
      emit(before.copyWith(entry: NameEntry.refusedBy(exception)));
      return;
    }
    final (changedClient, changedZones) = changed;
    emit(
      before.copyWith(
        status: ClientDetailStatus.saving,
        client: changedClient,
        zones: changedZones,
        entry: isNameEntry ? NameEntry.saving : null,
      ),
    );
    try {
      // A save without a zone list leaves the stored zones as they are, which is what a change to the client alone
      // needs.
      await _clients.save(changedClient, zones: identical(changedZones, zones) ? null : changedZones);
      if (isClosed) return;
      emit(state.copyWith(status: statusAfter, entry: isNameEntry ? NameEntry.saved : null));
    } on DomainException catch (exception) {
      // Storage applies the naming rule to the zones it holds, which can differ from the zones that were read.
      if (isClosed) return;
      _putBack(client, zones, refusedEntry: isNameEntry ? NameEntry.refusedBy(exception) : null);
    } on Exception catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      _putBack(client, zones, refusedEntry: isNameEntry ? NameEntry.failed : null);
    }
  }

  /// Shows [client] and [zones] again after storage did not take a change to them.
  ///
  /// A name dialog reads [refusedEntry] when the change came from one. Without it, the status tells the failure,
  /// and the name entry stays as it is at this moment, which can be later than the start of the change.
  void _putBack(Client client, ClientZones zones, {required NameEntry? refusedEntry}) {
    emit(
      state.copyWith(
        status: refusedEntry == null ? ClientDetailStatus.saveFailed : ClientDetailStatus.ready,
        client: client,
        zones: zones,
        entry: refusedEntry,
      ),
    );
  }
}
