// 📦 Package imports:
import 'package:sqflite/sqflite.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/upsert.dart';

/// Stores the clients and their zones in the `clients` and `zones` tables.
final class SqliteClientRepository implements ClientRepository {
  const new(this._database);

  final Database _database;

  @override
  Future<List<Client>> activeClients() async {
    final rows = await _database.query('clients', where: 'is_archived = 0', orderBy: 'created_at, id');
    return rows.map(_clientFromRow).toList();
  }

  @override
  Future<Client?> clientById(String id) async {
    final rows = await _database.query('clients', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _clientFromRow(rows.single);
  }

  @override
  Future<ClientZones> zonesOf(String clientId) => _zonesOf(_database, clientId);

  @override
  Future<void> save(Client client, {ClientZones? zones}) async {
    if (zones != null && zones.clientId != client.id) {
      throw ArgumentError.value(zones.clientId, 'zones', 'The zones belong to another client');
    }
    await _database.transaction((transaction) async {
      await upsert(
        transaction,
        'clients',
        key: {'id': client.id},
        values: {
          'name': client.name,
          'is_archived': client.isArchived ? 1 : 0,
          'created_at': client.createdAt.microsecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [client.id],
      );
      if (zones == null) return;
      for (final zone in zones.all) {
        // The update matches the zone only under its own client, so an identifier that another client uses makes the
        // insert fail and the transaction roll back.
        await upsert(
          transaction,
          'zones',
          key: {'id': zone.id, 'client_id': zone.clientId},
          values: {'name': zone.name, 'position': zone.position, 'is_active': zone.isActive ? 1 : 0},
          where: 'id = ? AND client_id = ?',
          whereArgs: [zone.id, zone.clientId],
        );
      }
      // The stored zones can hold a zone that [zones] does not, when [zones] came from an older read. Reading the
      // stored list applies the domain rules to all of it, and a broken rule rolls the transaction back.
      await _zonesOf(transaction, client.id);
    });
  }

  static Future<ClientZones> _zonesOf(DatabaseExecutor database, String clientId) async {
    final rows = await database.query('zones', where: 'client_id = ?', whereArgs: [clientId]);
    return ClientZones(clientId: clientId, zones: rows.map(_zoneFromRow));
  }

  static Client _clientFromRow(Map<String, Object?> row) => Client(
    id: row['id']! as String,
    name: row['name']! as String,
    createdAt: DateTime.fromMicrosecondsSinceEpoch(row['created_at']! as int, isUtc: true),
    isArchived: row['is_archived'] == 1,
  );

  static Zone _zoneFromRow(Map<String, Object?> row) => Zone(
    id: row['id']! as String,
    clientId: row['client_id']! as String,
    name: row['name']! as String,
    position: row['position']! as int,
    isActive: row['is_active'] == 1,
  );
}
