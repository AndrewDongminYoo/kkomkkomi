// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:bloc/bloc.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';

part 'client_list_state.dart';

/// Loads the active clients and adds a client while the plan of the company allows one more.
class ClientListCubit extends Cubit<ClientListState> {
  new({
    required this._clients,
    required this._entitlements,
    required this._idGenerator,
    required this._clock,
    this._planTimeout = defaultPlanTimeout,
  }) : super(const ClientListState());

  /// How long the check of the limit before a save waits for the plan. The dialog takes no touch while that check
  /// runs, so the check must end, and a plan that does not answer in time fails the save without naming a plan. An
  /// estimate that no device measured.
  static const defaultPlanTimeout = Duration(seconds: 10);

  final ClientRepository _clients;
  final Entitlements _entitlements;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final Duration _planTimeout;

  /// Reads the active clients from storage.
  ///
  /// The list that the state holds stays in place while storage answers, so a second call does not hide it. The
  /// answer forgets the plan whose limit stopped the last addition, because the list or the plan can have changed on
  /// another screen.
  Future<void> load() async {
    if (state.status == ClientListStatus.loadFailed) emit(state.copyWith(status: ClientListStatus.loading));
    try {
      final clients = await _clients.activeClients();
      if (isClosed) return;
      emit(state.copyWith(status: ClientListStatus.ready, clients: clients, limitPlan: () => null));
    } on Exception catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: ClientListStatus.loadFailed));
    }
  }

  /// Asks whether the plan of the company allows one more active client, after a press of the add control.
  ///
  /// [ClientListState.addition] becomes [ClientAddition.allowed] when it does, and the screen then opens the dialog
  /// for a new client. When it does not, [ClientListState.limitPlan] names the plan. A call while an earlier one is on
  /// its way does nothing.
  Future<void> requestNewClient() async {
    if (state.addition == ClientAddition.checking) return;
    emit(state.copyWith(addition: ClientAddition.checking));
    // Only the add control waits for the plan, so the check waits for the answer of the port, which gives the last
    // plan that it knew when the store does not answer.
    final plan = await _planAtLimit(_entitlements.currentPlan);
    if (isClosed) return;
    emit(
      state.copyWith(
        addition: plan == null ? ClientAddition.allowed : ClientAddition.idle,
        limitPlan: () => plan,
      ),
    );
  }

  /// Forgets what became of the last submitted name, before the dialog for a new client opens.
  void startNameEntry() => emit(state.copyWith(entry: NameEntry.editing, addition: ClientAddition.idle));

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
    // The plan can change while the dialog is open, for example at the end of a subscription, so the limit is checked
    // again right before the save. A plan that does not answer in time names no plan, so the save fails.
    final Plan? plan;
    try {
      plan = await _planAtLimit(() => _entitlements.currentPlan().timeout(_planTimeout));
    } on TimeoutException {
      if (isClosed) return;
      emit(state.copyWith(entry: NameEntry.failed));
      return;
    }
    if (isClosed) return;
    if (plan != null) {
      emit(state.copyWith(entry: NameEntry.limitReached, limitPlan: () => plan));
      return;
    }
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

  /// The plan whose limit the active clients reach, or null when the plan allows one more.
  ///
  /// Every plan allows a client below the Free limit, so [read], which reaches RevenueCat in the production flavor, is
  /// started only when the company has at least as many active clients as the Free limit: a function, so that the
  /// caller decides how long to wait. The port gives the last plan that it knew, and Free only before any answer of
  /// the store, so the limit holds as for Free only when the store never answered on this device.
  Future<Plan?> _planAtLimit(Future<Plan> Function() read) async {
    final count = state.clients.length;
    if (Plan.free.allowsAnotherClient(count)) return null;
    final plan = await read();
    return plan.allowsAnotherClient(count) ? null : plan;
  }
}
