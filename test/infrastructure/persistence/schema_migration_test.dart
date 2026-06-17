import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/persistence/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v2 -> v3 migration keeps repos at root and adds folders', () async {
    // Build a schema-v2 database by hand on a shared in-memory connection.
    final raw = sqlite3.openInMemory()
      ..execute('''
      CREATE TABLE repositories (
        id TEXT NOT NULL PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        color TEXT NULL,
        last_opened_utc TEXT NOT NULL,
        tab_order INTEGER NOT NULL,
        created_utc TEXT NOT NULL
      );
    ''')
      ..execute('''
      CREATE TABLE settings (
        key TEXT NOT NULL PRIMARY KEY,
        value_json TEXT NOT NULL
      );
    ''')
      ..execute('''
      CREATE TABLE activity_log (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        repo_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        summary TEXT NOT NULL,
        detail TEXT NULL,
        started_utc TEXT NOT NULL,
        succeeded INTEGER NOT NULL
      );
    ''')
      ..execute('''
      INSERT INTO repositories
        (id, path, display_name, color, last_opened_utc, tab_order, created_utc)
      VALUES ('r1', '/tmp/a', 'a', NULL, '2026-01-01T00:00:00.000Z', 5,
              '2026-01-01T00:00:00.000Z');
    ''')
      ..execute('PRAGMA user_version = 2');

    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    // Any query forces Drift to run onUpgrade(2 -> 3).
    final repos = await db.select(db.repositories).get();
    expect(repos, hasLength(1));
    expect(repos.single.tabOrder, 5);
    expect(repos.single.parentFolderId, isNull);

    // folders table now exists and is usable.
    final folders = await db.select(db.folders).get();
    expect(folders, isEmpty);

    await db.close();
  });

  test('fresh v3 database has folders table and parentFolderId column',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    expect(await db.select(db.folders).get(), isEmpty);
    final repos = await db.select(db.repositories).get();
    expect(repos, isEmpty); // column exists -> query compiles
    await db.close();
  });
}
