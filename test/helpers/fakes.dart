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

  /// The exception that every call throws while it is set.
  Exception? failure;

  /// A save waits for this completer while it is set, so that a test can act while a save is on its way.
  Completer<void>? gate;

  @override
  Future<void> save(Visit visit) async {
    await gate?.future;
    _throwFailure();
    _visits
      ..removeWhere((saved) => saved.id == visit.id)
      ..add(visit);
  }

  @override
  Future<Visit?> visitById(String id) async {
    _throwFailure();
    return _visits.where((visit) => visit.id == id).firstOrNull;
  }

  @override
  Future<List<Visit>> visitsOf(String clientId) async {
    _throwFailure();
    return _visits.where((visit) => visit.clientId == clientId).toList()..sort((a, b) => b.compareChronologically(a));
  }

  void _throwFailure() {
    if (failure case final failure?) throw failure;
  }
}

/// A camera that gives what a test put in [results], and never opens a camera.
class FakePhotoCapture implements PhotoCapture {
  /// What the next calls give, in order: the path of a photo file, null for a camera that the person closed, or
  /// an exception that the call throws.
  final results = <Object?>[];

  /// How many times the camera was opened.
  int calls = 0;

  /// A call waits for this completer while it is set, so that a test can act while the camera is open.
  Completer<void>? gate;

  @override
  Future<String?> takePhoto() async {
    calls++;
    await gate?.future;
    final result = results.removeAt(0);
    if (result is Exception) throw result;
    return result as String?;
  }
}

/// Keeps no file. It remembers which photo it gave for which source file and which photos it deleted.
class FakePhotoStore implements PhotoStore {
  /// The directory that the store gives as the root of every photo path.
  static const directory = '/documents';

  /// The source file of each photo that the store holds.
  final sources = <PhotoRef, String>{};

  /// The photos that the store was asked to delete, in order.
  final deleted = <PhotoRef>[];

  /// The exception that a save throws while it is set.
  Exception? saveFailure;

  /// The exception that a delete throws while it is set.
  Exception? deleteFailure;

  @override
  Future<PhotoRef> save({required String sourcePath, required String visitId, required String photoId}) async {
    if (saveFailure case final failure?) throw failure;
    final photo = PhotoRef('photos/$visitId/$photoId.jpg');
    sources[photo] = sourcePath;
    return photo;
  }

  @override
  Future<void> delete(PhotoRef photo) async {
    if (deleteFailure case final failure?) throw failure;
    deleted.add(photo);
    sources.remove(photo);
  }

  @override
  Future<String> directoryPath() async => directory;
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
