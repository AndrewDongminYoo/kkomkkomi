import 'package:kkomkkomi/domain/domain.dart';

/// Stores the clients and their zones.
abstract interface class ClientRepository {
  /// The clients that are not archived, oldest first.
  Future<List<Client>> activeClients();

  /// The client with [id], or null when none exists.
  Future<Client?> clientById(String id);

  /// The zones of the client with [clientId], removed zones included.
  ///
  /// The result holds no zone when the client has none or does not exist.
  Future<ClientZones> zonesOf(String clientId);

  /// Saves [client] and, when [zones] is given, each zone in it, in one transaction.
  ///
  /// A stored zone that [zones] does not hold stays as it is, because a zone is never deleted.
  /// Throws a [DuplicateZoneNameException], and saves nothing, when the stored zones would break the naming rule
  /// after the save, which can happen when [zones] was read before another save.
  /// Throws an [ArgumentError] when [zones] belongs to another client.
  Future<void> save(Client client, {ClientZones? zones});
}
