// 📦 Package imports:
import 'package:sqflite/sqflite.dart';

/// The version of the schema that [createSchema] creates.
const schemaVersion = 8;

// No row of `clients`, `zones`, or `visits` is deleted alone, so the foreign keys declare no delete action. The erase of
// all data deletes the rows of every table at once, children first.
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
// `client_pages` and `publish_jobs` is not deleted alone either: a revoked page keeps its row, and a job keeps the state
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

// Version 3 adds the one capture that has the camera open. Its columns declare no foreign key: the start of the app
// checks that the visit and the zone record exist, and removes a row that names one that does not.
const _version3 = [
  '''
CREATE TABLE open_capture (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  visit_id TEXT NOT NULL,
  zone_id TEXT NOT NULL,
  slot TEXT NOT NULL
)''',
];

// Version 4 keeps deletion intent separate from locally recorded backend acknowledgement.
const _version4 = [
  'ALTER TABLE client_pages ADD COLUMN server_delete_requested_at INTEGER',
  'ALTER TABLE client_pages ADD COLUMN server_deleted_at INTEGER',
];

// Version 5 adds the status of a zone record and the reason of an exception. A record that an earlier version stored
// reads as done with no reason.
const _version5 = [
  "ALTER TABLE zone_records ADD COLUMN status TEXT NOT NULL DEFAULT 'done'",
  "ALTER TABLE zone_records ADD COLUMN reason TEXT NOT NULL DEFAULT ''",
];

// Version 6 adds the optional business phone, leaving an empty phone for existing company profiles.
const _version6 = ["ALTER TABLE company_profile ADD COLUMN phone TEXT NOT NULL DEFAULT ''"];

const _version7 = [
  "ALTER TABLE zone_records ADD COLUMN before_photo_source TEXT NOT NULL DEFAULT 'unknown'",
  "ALTER TABLE zone_records ADD COLUMN after_photo_source TEXT NOT NULL DEFAULT 'unknown'",
  "ALTER TABLE open_capture ADD COLUMN source TEXT NOT NULL DEFAULT 'unknown'",
];

const _version8 = [
  'ALTER TABLE zone_records ADD COLUMN before_captured_at INTEGER',
  'ALTER TABLE zone_records ADD COLUMN after_captured_at INTEGER',
];

/// The statements that take the schema from each version to the next, in order: the first item makes version 1.
const List<List<String>> _migrations = [
  _version1,
  _version2,
  _version3,
  _version4,
  _version5,
  _version6,
  _version7,
  _version8,
];

/// Creates the schema of [schemaVersion]: one table for each of the company profile, clients, zones, visits, and
/// zone records, the tables of publishing, and the table of the capture that has the camera open.
///
/// Time columns hold microseconds since the epoch in UTC, and `visit_date` holds
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
