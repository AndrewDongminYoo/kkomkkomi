// 🌎 Project imports:
import 'package:kkomkkomi/application/client_repository.dart';
import 'package:kkomkkomi/application/clock.dart';
import 'package:kkomkkomi/application/id_generator.dart';
import 'package:kkomkkomi/application/visit_repository.dart';
import 'package:kkomkkomi/domain/domain.dart';

/// No client has [clientId].
final class ClientNotFoundException implements Exception {
  const new(this.clientId);

  final String clientId;
}

/// Starts a visit from the active zones of a client and saves it.
final class StartVisit {
  const new({
    required this._clients,
    required this._visits,
    required this._idGenerator,
    required this._clock,
  });

  final ClientRepository _clients;
  final VisitRepository _visits;
  final IdGenerator _idGenerator;
  final Clock _clock;

  /// Throws a [ClientNotFoundException] when no client has [clientId].
  Future<Visit> call({required String clientId, required VisitDate visitDate}) async {
    if (await _clients.clientById(clientId) == null) throw ClientNotFoundException(clientId);
    final visit = Visit.start(
      id: _idGenerator.newId(),
      zones: await _clients.zonesOf(clientId),
      visitDate: visitDate,
      createdAt: _clock.now(),
    );
    await _visits.save(visit);
    return visit;
  }
}
