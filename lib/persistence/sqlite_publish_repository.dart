import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/persistence/upsert.dart';
import 'package:sqflite/sqflite.dart';

/// Stores the client pages, the publish jobs, and the uploaded photos in the `client_pages`, `publish_jobs`, and
/// `published_photos` tables.
final class SqlitePublishRepository implements PublishRepository {
  const new(this._database);

  final Database _database;

  @override
  Future<ClientPage?> openPageOf(String clientId, {ClientPage Function()? create}) =>
      _database.transaction((transaction) async {
        final rows = await transaction.query(
          'client_pages',
          where: 'client_id = ? AND revoked_at IS NULL',
          whereArgs: [clientId],
        );
        if (rows.isNotEmpty) return _pageFromRow(rows.single);
        if (create == null) return null;
        final page = create();
        await transaction.insert('client_pages', _pageToRow(page));
        return page;
      });

  @override
  Future<ClientPage?> pageById(String id) async {
    final rows = await _database.query('client_pages', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _pageFromRow(rows.single);
  }

  @override
  Future<List<ClientPage>> pages() async {
    final rows = await _database.query('client_pages', orderBy: 'created_at, rowid');
    return rows.map(_pageFromRow).toList();
  }

  @override
  Future<PublishJob> enqueue(PublishJob job) => _database.transaction((transaction) async {
    final rows = await transaction.query(
      'publish_jobs',
      where: 'kind = ? AND page_id = ? AND visit_id IS ? AND status = ?',
      whereArgs: [job.kind.name, job.pageId, job.visitId, PublishJobStatus.pending.name],
    );
    if (rows.isEmpty) {
      await transaction.insert('publish_jobs', _jobToRow(job));
      return job;
    }
    final pending = _jobFromRow(rows.single).restart();
    await _updateJob(transaction, pending);
    return pending;
  });

  @override
  Future<bool> revoke(
    ClientPage page, {
    required DateTime at,
    required PublishJob revokeJob,
    ClientPage? replacement,
    PublishJob Function(String visitId)? republish,
  }) => _database.transaction((transaction) async {
    final revoked = await transaction.update(
      'client_pages',
      {'revoked_at': at.toUtc().microsecondsSinceEpoch},
      where: 'id = ? AND revoked_at IS NULL',
      whereArgs: [page.id],
    );
    if (revoked == 0) return false;
    final published = await transaction.query(
      'publish_jobs',
      columns: ['visit_id'],
      where: 'page_id = ? AND kind = ? AND status IN (?, ?)',
      whereArgs: [page.id, PublishJobKind.publish.name, PublishJobStatus.pending.name, PublishJobStatus.done.name],
      orderBy: 'created_at, rowid',
    );
    final pending = await transaction.query(
      'publish_jobs',
      where: 'page_id = ? AND kind = ? AND status = ?',
      whereArgs: [page.id, PublishJobKind.publish.name, PublishJobStatus.pending.name],
    );
    for (final row in pending) {
      await _updateJob(transaction, _jobFromRow(row).fail(PublishFailure.revoked));
    }
    await transaction.insert('publish_jobs', _jobToRow(revokeJob));
    if (replacement == null) return true;
    await transaction.insert('client_pages', _pageToRow(replacement));
    if (republish != null) {
      for (final visitId in {for (final row in published) row['visit_id']! as String}) {
        await transaction.insert('publish_jobs', _jobToRow(republish(visitId)));
      }
    }
    return true;
  });

  @override
  Future<bool> saveJob(PublishJob job) async {
    final saved = await _database.update(
      'publish_jobs',
      _jobToRow(job),
      where: 'id = ? AND status = ? AND generation = ?',
      whereArgs: [job.id, PublishJobStatus.pending.name, job.generation],
    );
    return saved == 1;
  }

  @override
  Future<List<PublishJob>> pendingJobs() async {
    final rows = await _database.query(
      'publish_jobs',
      where: 'status = ?',
      whereArgs: [PublishJobStatus.pending.name],
      orderBy: 'created_at, rowid',
    );
    return rows.map(_jobFromRow).toList();
  }

  @override
  Future<void> stopPendingJobs(PublishFailure reason) => _database.transaction((transaction) async {
    final rows = await transaction.query(
      'publish_jobs',
      where: 'status = ?',
      whereArgs: [PublishJobStatus.pending.name],
    );
    for (final row in rows) {
      await _updateJob(transaction, _jobFromRow(row).fail(reason));
    }
  });

  @override
  Future<List<PublishJob>> jobsOfPage(String pageId) async {
    final rows = await _database.query(
      'publish_jobs',
      where: 'page_id = ?',
      whereArgs: [pageId],
      orderBy: 'created_at, rowid',
    );
    return rows.map(_jobFromRow).toList();
  }

  @override
  Future<void> clearRetryDelays() => _database.update(
    'publish_jobs',
    {'next_attempt_at': null},
    where: 'status = ?',
    whereArgs: [PublishJobStatus.pending.name],
  );

  @override
  Future<String?> uploadedPhoto({required String pageId, required String objectPath}) async {
    final rows = await _database.query(
      'published_photos',
      columns: ['photo_path'],
      where: 'page_id = ? AND object_path = ? AND arrived = 1',
      whereArgs: [pageId, objectPath],
    );
    return rows.isEmpty ? null : rows.single['photo_path']! as String;
  }

  @override
  Future<void> recordUploadIntent({required String pageId, required String objectPath, required String photoPath}) =>
      _database.insert('published_photos', {
        'page_id': pageId,
        'object_path': objectPath,
        'photo_path': photoPath,
        'arrived': 0,
        // A record that exists, of an upload that started or arrived before, stays as it is.
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

  @override
  Future<void> saveUploadedPhoto({required String pageId, required String objectPath, required String photoPath}) =>
      // The key is the page and the object, so a new photo file of the same slot takes the place of the old one.
      _database.transaction(
        (transaction) => upsert(
          transaction,
          'published_photos',
          key: {'page_id': pageId, 'object_path': objectPath},
          values: {'photo_path': photoPath, 'arrived': 1},
          where: 'page_id = ? AND object_path = ?',
          whereArgs: [pageId, objectPath],
        ),
      );

  @override
  Future<List<String>> uploadedObjects(String pageId) async {
    final rows = await _database.query(
      'published_photos',
      columns: ['object_path'],
      where: 'page_id = ?',
      whereArgs: [pageId],
      orderBy: 'object_path',
    );
    return [for (final row in rows) row['object_path']! as String];
  }

  @override
  Future<void> removeUploadedPhoto({required String pageId, required String objectPath}) => _database.delete(
    'published_photos',
    where: 'page_id = ? AND object_path = ?',
    whereArgs: [pageId, objectPath],
  );

  @override
  Future<void> forgetArrivedUploads() => _database.transaction(
    (transaction) => transaction.update('published_photos', {'arrived': 0}, where: 'arrived = 1'),
  );

  static Future<void> _updateJob(DatabaseExecutor database, PublishJob job) =>
      database.update('publish_jobs', _jobToRow(job), where: 'id = ?', whereArgs: [job.id]);

  static Map<String, Object?> _pageToRow(ClientPage page) => {
    'id': page.id,
    'client_id': page.clientId,
    'created_at': page.createdAt.microsecondsSinceEpoch,
    'revoked_at': page.revokedAt?.microsecondsSinceEpoch,
  };

  static ClientPage _pageFromRow(Map<String, Object?> row) => ClientPage(
    id: row['id']! as String,
    clientId: row['client_id']! as String,
    createdAt: _time(row['created_at'])!,
    revokedAt: _time(row['revoked_at']),
  );

  static Map<String, Object?> _jobToRow(PublishJob job) => {
    'id': job.id,
    'kind': job.kind.name,
    'page_id': job.pageId,
    'visit_id': job.visitId,
    'created_at': job.createdAt.microsecondsSinceEpoch,
    'status': job.status.name,
    'attempts': job.attempts,
    'next_attempt_at': job.nextAttemptAt?.microsecondsSinceEpoch,
    'failure': job.failure?.name,
    'generation': job.generation,
  };

  static PublishJob _jobFromRow(Map<String, Object?> row) => PublishJob(
    id: row['id']! as String,
    kind: PublishJobKind.values.byName(row['kind']! as String),
    pageId: row['page_id']! as String,
    visitId: row['visit_id'] as String?,
    createdAt: _time(row['created_at'])!,
    status: PublishJobStatus.values.byName(row['status']! as String),
    attempts: row['attempts']! as int,
    nextAttemptAt: _time(row['next_attempt_at']),
    failure: switch (row['failure']) {
      final String name => PublishFailure.values.byName(name),
      _ => null,
    },
    generation: row['generation']! as int,
  );

  static DateTime? _time(Object? microseconds) =>
      microseconds is int ? DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true) : null;
}
