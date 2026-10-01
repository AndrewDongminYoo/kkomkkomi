import 'package:sqflite/sqflite.dart';

/// The version of the schema that [createSchema] creates.
const schemaVersion = 1;

// No row of `clients`, `zones`, or `visits` is ever deleted, so the foreign keys declare no delete action.
const _version1 = [
  '''
CREATE TABLE company_profile (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  name TEXT NOT NULL
)''',
  '''
CREATE TABLE clients (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  is_archived INTEGER NOT NULL,
  created_at INTEGER NOT NULL
)''',
  '''
CREATE TABLE zones (
  id TEXT NOT NULL PRIMARY KEY,
  client_id TEXT NOT NULL REFERENCES clients (id),
  name TEXT NOT NULL,
  position INTEGER NOT NULL,
  is_active INTEGER NOT NULL
)''',
  'CREATE INDEX zones_client_id ON zones (client_id)',
  '''
CREATE TABLE visits (
  id TEXT NOT NULL PRIMARY KEY,
  client_id TEXT NOT NULL REFERENCES clients (id),
  visit_date INTEGER NOT NULL,
  created_at INTEGER NOT NULL
)''',
  'CREATE INDEX visits_client_id ON visits (client_id)',
  '''
CREATE TABLE zone_records (
  visit_id TEXT NOT NULL REFERENCES visits (id),
  zone_id TEXT NOT NULL REFERENCES zones (id),
  position INTEGER NOT NULL,
  zone_name TEXT NOT NULL,
  before_photo TEXT,
  after_photo TEXT,
  note TEXT NOT NULL,
  PRIMARY KEY (visit_id, zone_id)
)''',
];

/// Creates the version 1 schema: one table for each of the company profile, clients, zones, visits, and zone records.
///
/// `created_at` holds microseconds since the epoch in UTC, and `visit_date` holds the calendar date as the number
/// `YYYYMMDD`.
Future<void> createSchema(DatabaseExecutor database) async {
  for (final statement in _version1) {
    await database.execute(statement);
  }
}
