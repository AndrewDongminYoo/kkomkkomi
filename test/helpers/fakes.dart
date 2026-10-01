import 'dart:async';

import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

/// Makes the identifiers `id-1`, `id-2`, and so on.
class SequenceIdGenerator implements IdGenerator {
  var _next = 1;

  @override
  String newId() => 'id-${_next++}';
}

/// Tells one fixed time.
class FixedClock implements Clock {
  const new(this.time);

  final DateTime time;

  @override
  DateTime now() => time;
}

/// Keeps the clients and their zones in memory, for a widget test that follows a change through the screens.
///
/// A save replaces the whole zone list of the client, which is enough for callers that save every zone they read.
class FakeClientRepository implements ClientRepository {
  new({Iterable<Client> clients = const [], Iterable<ClientZones> zones = const []}) {
    for (final client in clients) {
      _clients[client.id] = client;
    }
    for (final clientZones in zones) {
      _zones[clientZones.clientId] = clientZones;
    }
  }

  final _clients = <String, Client>{};
  final _zones = <String, ClientZones>{};

  /// The exception that every call throws while it is set.
  Exception? failure;

  /// A save waits for this completer while it is set, so that a test can act while a save is on its way.
  ///
  /// The save fails when the completer completes with an error.
  Completer<void>? gate;

  @override
  Future<List<Client>> activeClients() async {
    _throwFailure();
    return _clients.values.where((client) => !client.isArchived).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<Client?> clientById(String id) async {
    _throwFailure();
    return _clients[id];
  }

  @override
  Future<ClientZones> zonesOf(String clientId) async {
    _throwFailure();
    return _zones[clientId] ?? ClientZones(clientId: clientId);
  }

  @override
  Future<void> save(Client client, {ClientZones? zones}) async {
    await gate?.future;
    _throwFailure();
    _clients[client.id] = client;
    if (zones != null) _zones[client.id] = zones;
  }

  void _throwFailure() {
    if (failure case final failure?) throw failure;
  }
}

/// Keeps visits in memory.
class FakeVisitRepository implements VisitRepository {
  new({Iterable<Visit> visits = const []}) : _visits = visits.toList();

  final List<Visit> _visits;

  @override
  Future<void> save(Visit visit) async {
    _visits
      ..removeWhere((saved) => saved.id == visit.id)
      ..add(visit);
  }

  @override
  Future<Visit?> visitById(String id) async => _visits.where((visit) => visit.id == id).firstOrNull;

  @override
  Future<List<Visit>> visitsOf(String clientId) async =>
      _visits.where((visit) => visit.clientId == clientId).toList()..sort((a, b) => b.compareChronologically(a));
}

/// Keeps the company profile in memory.
class FakeCompanyProfileRepository implements CompanyProfileRepository {
  new({this.profile});

  CompanyProfile? profile;

  /// The exception that every call throws while it is set.
  Exception? failure;

  /// A save waits for this completer while it is set, so that a test can act while a save is on its way.
  ///
  /// The save fails when the completer completes with an error.
  Completer<void>? gate;

  @override
  Future<CompanyProfile?> load() async {
    if (failure case final failure?) throw failure;
    return profile;
  }

  @override
  Future<void> save(CompanyProfile profile) async {
    await gate?.future;
    if (failure case final failure?) throw failure;
    this.profile = profile;
  }
}
