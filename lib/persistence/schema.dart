import 'package:sqflite/sqflite.dart';

/// The version of the schema that [createSchema] creates.
const schemaVersion = 2;

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

// Version 2 adds the client pages, the publish jobs, and the photos that reached the backend. A row of
// `client_pages` and `publish_jobs` is never deleted either: a revoked page keeps its row, and a job keeps the state
// that it ended in.
const _version2 = [
  '''
CREATE TABLE client_pages (
  id TEXT NOT NULL PRIMARY KEY,
  client_id TEXT NOT NULL REFERENCES clients (id),
  created_at INTEGER NOT NULL,
  revoked_at INTEGER
)''',
  'CREATE INDEX client_pages_client_id ON client_pages (client_id)',
  '''
CREATE TABLE publish_jobs (
  id TEXT NOT NULL PRIMARY KEY,
  kind TEXT NOT NULL,
  page_id TEXT NOT NULL REFERENCES client_pages (id),
  visit_id TEXT REFERENCES visits (id),
  created_at INTEGER NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL,
  next_attempt_at INTEGER,
  failure TEXT,
  generation INTEGER NOT NULL
)''',
  'CREATE INDEX publish_jobs_page_id ON publish_jobs (page_id)',
  '''
CREATE TABLE published_photos (
  page_id TEXT NOT NULL REFERENCES client_pages (id),
  object_path TEXT NOT NULL,
  photo_path TEXT NOT NULL,
  arrived INTEGER NOT NULL,
  PRIMARY KEY (page_id, object_path)
)''',
];

/// The statements that take the schema from each version to the next, in order: the first item makes version 1.
const List<List<String>> _migrations = [_version1, _version2];

/// Creates the schema of [schemaVersion]: one table for each of the company profile, clients, zones, visits, and
/// zone records, and the tables of publishing.
///
/// `created_at`, `revoked_at`, and `next_attempt_at` hold microseconds since the epoch in UTC, and `visit_date` holds
/// the calendar date as the number `YYYYMMDD`.
Future<void> createSchema(DatabaseExecutor database) => upgradeSchema(database, from: 0);

/// Takes the schema of a database from version [from] to version [to].
Future<void> upgradeSchema(DatabaseExecutor database, {required int from, int to = schemaVersion}) async {
  for (final statements in _migrations.sublist(from, to)) {
    for (final statement in statements) {
      await database.execute(statement);
    }
  }
}
