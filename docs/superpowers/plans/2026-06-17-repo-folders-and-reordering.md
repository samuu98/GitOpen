# Repository Folders & Reordering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn GitOpen's flat repo dropdown into a persistent, organizable catalog where every known repo lives in a collapsible nested-folder tree, with drag reorder/reparent of repos and folders, persisted across sessions.

**Architecture:** A new `folders` Drift table plus a `parentFolderId` column on `repositories` (schema v3) model an adjacency-list tree. A pure `buildRepoTree` function turns folders + placed repos into a `RepoTreeNode` tree. A `RepoTreeStore` port (Drift-backed) owns all folder CRUD and shared-`sortOrder` reorder/reparent in transactions. A `RepoOrganizer` StateNotifier exposes the tree to a custom `OverlayPortal` popover that renders the tree and hand-built drag & drop. The repo set becomes the full catalog (one active repo, restored via a `last_active_repo` setting).

**Tech Stack:** Flutter, Riverpod (`StateNotifier`), Drift (SQLite), `flutter_test`. No new dependencies (DnD is hand-built, consistent with the project's hand-rolled commit graph).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-06-17-repo-folders-and-reordering-design.md`.
- Drift column names are snake_case derived from camelCase getters (`parentFolderId` → `parent_folder_id`).
- `DriftDatabaseOptions(storeDateTimeAsText: true)` — all DateTime columns stored as text.
- Tests mirror `lib/` under `test/`; `test/_helpers/in_memory_db.dart` exposes `newInMemoryDb()` → `AppDatabase.forTesting(NativeDatabase.memory())`.
- Drift codegen runs with `dart run build_runner build --delete-conflicting-outputs` (config in `build.yaml`).
- PR CI runs exactly `flutter analyze` + `flutter test`; both must stay green. Keep lines within the analyzer's width (wrap at ~80 cols as the codebase does).
- IDs are 32-hex-char strings generated like `RepoId.newId()` (16 secure-random bytes, hex).
- `RepoLocation(id, path, displayName)` is the existing repo value object; `RepoId(value)` / `RepoId.newId()` exist.
- Git identity for commits on this repo: `zN3utr4l`. Branch: `feat/repo-folders-and-reordering`.

---

### Task 1: Domain — `FolderId` and `Folder`

**Files:**
- Create: `lib/domain/repositories/folder_id.dart`
- Create: `lib/domain/repositories/folder.dart`
- Test: `test/domain/repositories/folder_test.dart`

**Interfaces:**
- Consumes: `RepoId` pattern (`package:equatable`).
- Produces:
  - `FolderId` — `const FolderId(String value)`, `factory FolderId.newId()`, Equatable on `value`, `toString() => value`.
  - `Folder` — `const Folder({required FolderId id, required String name, FolderId? parentId, required int sortOrder, required bool collapsed})`, Equatable on all fields, `copyWith(...)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/repositories/folder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';

void main() {
  group('FolderId', () {
    test('newId generates a 32-char hex string', () {
      final id = FolderId.newId();
      expect(id.value, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id.value), isTrue);
    });

    test('equality is by value', () {
      expect(const FolderId('a'), const FolderId('a'));
      expect(const FolderId('a'), isNot(const FolderId('b')));
    });
  });

  group('Folder', () {
    test('copyWith replaces only the given fields', () {
      const f = Folder(
        id: FolderId('f1'),
        name: 'Work',
        parentId: null,
        sortOrder: 0,
        collapsed: false,
      );
      final renamed = f.copyWith(name: 'Personal', collapsed: true);
      expect(renamed.name, 'Personal');
      expect(renamed.collapsed, isTrue);
      expect(renamed.id, const FolderId('f1'));
      expect(renamed.sortOrder, 0);
    });

    test('equality is structural', () {
      const a = Folder(
        id: FolderId('f1'), name: 'Work', parentId: null,
        sortOrder: 0, collapsed: false,
      );
      const b = Folder(
        id: FolderId('f1'), name: 'Work', parentId: null,
        sortOrder: 0, collapsed: false,
      );
      expect(a, b);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/repositories/folder_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:gitopen/domain/repositories/folder.dart'`.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/domain/repositories/folder_id.dart
import 'dart:math' as math;
import 'package:equatable/equatable.dart';

final class FolderId extends Equatable {
  const FolderId(this.value);

  factory FolderId.newId() {
    final r = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return FolderId(bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
  }
  final String value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => value;
}
```

```dart
// lib/domain/repositories/folder.dart
import 'package:equatable/equatable.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';

final class Folder extends Equatable {
  const Folder({
    required this.id,
    required this.name,
    required this.parentId,
    required this.sortOrder,
    required this.collapsed,
  });

  final FolderId id;
  final String name;
  final FolderId? parentId;
  final int sortOrder;
  final bool collapsed;

  Folder copyWith({
    String? name,
    FolderId? parentId,
    bool clearParent = false,
    int? sortOrder,
    bool? collapsed,
  }) {
    return Folder(
      id: id,
      name: name ?? this.name,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      sortOrder: sortOrder ?? this.sortOrder,
      collapsed: collapsed ?? this.collapsed,
    );
  }

  @override
  List<Object?> get props => [id, name, parentId, sortOrder, collapsed];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/repositories/folder_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/repositories/folder_id.dart lib/domain/repositories/folder.dart test/domain/repositories/folder_test.dart
git commit -m "feat(repos): add Folder and FolderId domain types"
```

---

### Task 2: Schema v3 — `folders` table + `parentFolderId` column + migration

**Files:**
- Create: `lib/infrastructure/persistence/tables/folders_table.dart`
- Modify: `lib/infrastructure/persistence/tables/repositories_table.dart` (add `parentFolderId`, document `tabOrder`)
- Modify: `lib/infrastructure/persistence/database.dart` (`schemaVersion` 3, register `Folders`, `onUpgrade` from<3)
- Regenerate: `lib/infrastructure/persistence/database.g.dart`
- Test: `test/infrastructure/persistence/schema_migration_test.dart`

**Interfaces:**
- Produces: Drift table `Folders` with columns `id, name, parentId, sortOrder, collapsed, createdUtc`; `Repositories.parentFolderId` (TEXT NULL). `db.folders` and `db.repositories.parentFolderId` accessors after codegen.

- [ ] **Step 1: Write the failing migration test**

```dart
// test/infrastructure/persistence/schema_migration_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/persistence/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v2 -> v3 migration keeps repos at root and adds folders', () async {
    // Build a schema-v2 database by hand on a shared in-memory connection.
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE repositories (
        id TEXT NOT NULL PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        color TEXT NULL,
        last_opened_utc TEXT NOT NULL,
        tab_order INTEGER NOT NULL,
        created_utc TEXT NOT NULL
      );
    ''');
    raw.execute('''
      CREATE TABLE settings (key TEXT NOT NULL PRIMARY KEY, value_json TEXT NOT NULL);
    ''');
    raw.execute('''
      CREATE TABLE activity_log (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        repo_id TEXT NOT NULL, kind TEXT NOT NULL, summary TEXT NOT NULL,
        detail TEXT NULL, started_utc TEXT NOT NULL, succeeded INTEGER NOT NULL
      );
    ''');
    raw.execute('''
      INSERT INTO repositories
        (id, path, display_name, color, last_opened_utc, tab_order, created_utc)
      VALUES ('r1', '/tmp/a', 'a', NULL, '2026-01-01T00:00:00.000Z', 5,
              '2026-01-01T00:00:00.000Z');
    ''');
    raw.execute('PRAGMA user_version = 2');

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

  test('fresh v3 database has folders table and parentFolderId column', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    expect(await db.select(db.folders).get(), isEmpty);
    final repos = await db.select(db.repositories).get();
    expect(repos, isEmpty); // column exists -> query compiles
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/infrastructure/persistence/schema_migration_test.dart`
Expected: FAIL — `db.folders` getter does not exist / compile error.

- [ ] **Step 3: Create the folders table**

```dart
// lib/infrastructure/persistence/tables/folders_table.dart
import 'package:drift/drift.dart';

class Folders extends Table {
  TextColumn get id => text().withLength(min: 32, max: 32)();
  TextColumn get name => text()();
  // Null parentId == root-level folder.
  TextColumn get parentId => text().nullable()();
  // Order within the parent's shared (folders + repos) sort space.
  IntColumn get sortOrder => integer()();
  BoolColumn get collapsed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

- [ ] **Step 4: Add `parentFolderId` to the repositories table**

```dart
// lib/infrastructure/persistence/tables/repositories_table.dart
import 'package:drift/drift.dart';

class Repositories extends Table {
  TextColumn get id => text().withLength(min: 32, max: 32)();
  TextColumn get path => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get color => text().nullable()();
  DateTimeColumn get lastOpenedUtc => dateTime()();
  // Order within this repo's parent folder (shared with sibling folders).
  // Historically named "tabOrder"; kept to avoid a column rename migration.
  IntColumn get tabOrder => integer()();
  // Null parentFolderId == root-level repo.
  TextColumn get parentFolderId => text().nullable()();
  DateTimeColumn get createdUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

- [ ] **Step 5: Bump schema version and add the migration**

In `lib/infrastructure/persistence/database.dart`: add the import, register the table, bump version, extend `onUpgrade`.

```dart
import 'package:gitopen/infrastructure/persistence/tables/folders_table.dart';
// ...
@DriftDatabase(tables: [Repositories, Settings, ActivityLog, Folders])
class AppDatabase extends _$AppDatabase {
  // ... constructors unchanged ...

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(activityLog);
      }
      if (from < 3) {
        await m.createTable(folders);
        await m.addColumn(repositories, repositories.parentFolderId);
      }
    },
  );
  // ... options unchanged ...
}
```

- [ ] **Step 6: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `database.g.dart` updated; build succeeds with no errors.

- [ ] **Step 7: Run the migration test**

Run: `flutter test test/infrastructure/persistence/schema_migration_test.dart`
Expected: PASS (both tests).

- [ ] **Step 8: Commit**

```bash
git add lib/infrastructure/persistence/tables/folders_table.dart lib/infrastructure/persistence/tables/repositories_table.dart lib/infrastructure/persistence/database.dart lib/infrastructure/persistence/database.g.dart test/infrastructure/persistence/schema_migration_test.dart
git commit -m "feat(repos): schema v3 with folders table and repo parentFolderId"
```

---

### Task 3: Pure `buildRepoTree` + `RepoTreeNode`

**Files:**
- Create: `lib/application/workspaces/repo_tree_node.dart`
- Create: `lib/application/workspaces/build_repo_tree.dart`
- Test: `test/application/workspaces/build_repo_tree_test.dart`

**Interfaces:**
- Consumes: `Folder`, `FolderId`, `RepoLocation`, `RepoId`.
- Produces:
  - `PlacedRepo` — `const PlacedRepo({required RepoLocation location, required FolderId? parentId, required int sortOrder})`.
  - `sealed class RepoTreeNode { int get sortOrder; }`
    - `FolderNode(Folder folder, List<RepoTreeNode> children)` — `sortOrder => folder.sortOrder`.
    - `RepoNode(RepoLocation location, int sortOrder)`.
  - `List<RepoTreeNode> buildRepoTree(List<Folder> folders, List<PlacedRepo> repos)` — roots sorted by `sortOrder`; children recursively sorted; orphan folders (missing parent) re-rooted; cycles broken by re-rooting the node whose ancestry loops back to itself.

- [ ] **Step 1: Write the failing test**

```dart
// test/application/workspaces/build_repo_tree_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/workspaces/build_repo_tree.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

Folder _folder(String id, String name, {String? parent, int order = 0}) =>
    Folder(
      id: FolderId(id), name: name,
      parentId: parent == null ? null : FolderId(parent),
      sortOrder: order, collapsed: false,
    );

PlacedRepo _repo(String id, {String? parent, int order = 0}) => PlacedRepo(
      location: RepoLocation(RepoId(id), '/p/$id', id),
      parentId: parent == null ? null : FolderId(parent),
      sortOrder: order,
    );

void main() {
  group('buildRepoTree', () {
    test('nests repos under their folders', () {
      final tree = buildRepoTree(
        [_folder('w', 'Work', order: 0)],
        [_repo('a', parent: 'w', order: 0)],
      );
      expect(tree, hasLength(1));
      final work = tree.single as FolderNode;
      expect(work.folder.name, 'Work');
      expect(work.children.single, isA<RepoNode>());
    });

    test('interleaves folders and repos by shared sortOrder', () {
      final tree = buildRepoTree(
        [_folder('w', 'Work', order: 1)],
        [_repo('a', order: 0), _repo('b', order: 2)],
      );
      expect(tree.map((n) => n.sortOrder), [0, 1, 2]);
      expect(tree[0], isA<RepoNode>());
      expect(tree[1], isA<FolderNode>());
      expect(tree[2], isA<RepoNode>());
    });

    test('re-roots a folder whose parent is missing', () {
      final tree = buildRepoTree(
        [_folder('child', 'Child', parent: 'ghost', order: 0)],
        const [],
      );
      expect(tree, hasLength(1));
      expect((tree.single as FolderNode).folder.id, const FolderId('child'));
    });

    test('breaks a parent cycle by re-rooting', () {
      // a -> b -> a (cycle)
      final tree = buildRepoTree(
        [
          _folder('a', 'A', parent: 'b'),
          _folder('b', 'B', parent: 'a'),
        ],
        const [],
      );
      // No infinite loop; both folders surface (re-rooted) without duplication.
      final ids = <FolderId>[];
      void walk(List<RepoTreeNode> nodes) {
        for (final n in nodes) {
          if (n is FolderNode) {
            ids.add(n.folder.id);
            walk(n.children);
          }
        }
      }
      walk(tree);
      expect(ids.toSet(), {const FolderId('a'), const FolderId('b')});
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/application/workspaces/build_repo_tree_test.dart`
Expected: FAIL — files don't exist.

- [ ] **Step 3: Write `RepoTreeNode`**

```dart
// lib/application/workspaces/repo_tree_node.dart
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

class PlacedRepo {
  const PlacedRepo({
    required this.location,
    required this.parentId,
    required this.sortOrder,
  });
  final RepoLocation location;
  final FolderId? parentId;
  final int sortOrder;
}

sealed class RepoTreeNode {
  int get sortOrder;
}

final class FolderNode extends RepoTreeNode {
  FolderNode(this.folder, this.children);
  final Folder folder;
  final List<RepoTreeNode> children;
  @override
  int get sortOrder => folder.sortOrder;
}

final class RepoNode extends RepoTreeNode {
  RepoNode(this.location, this.sortOrder);
  final RepoLocation location;
  @override
  final int sortOrder;
}
```

- [ ] **Step 4: Write `buildRepoTree`**

```dart
// lib/application/workspaces/build_repo_tree.dart
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';

/// Pure: builds the root-level node list from folders + placed repos.
/// Defensive against corrupt data — orphan folders (missing parent) and
/// folders caught in a parent cycle are treated as root-level.
List<RepoTreeNode> buildRepoTree(
  List<Folder> folders,
  List<PlacedRepo> repos,
) {
  final byId = {for (final f in folders) f.id: f};

  // A folder's effective parent is null if the chain is broken or loops.
  FolderId? effectiveParent(Folder f) {
    if (f.parentId == null) return null;
    final seen = <FolderId>{f.id};
    var cursor = f.parentId;
    while (cursor != null) {
      if (seen.contains(cursor)) return null; // cycle -> re-root
      final parent = byId[cursor];
      if (parent == null) return null; // missing ancestor -> re-root
      seen.add(cursor);
      cursor = parent.parentId;
    }
    return f.parentId; // chain reaches a root cleanly
  }

  final childFolders = <FolderId?, List<Folder>>{};
  for (final f in folders) {
    childFolders.putIfAbsent(effectiveParent(f), () => []).add(f);
  }
  final childRepos = <FolderId?, List<PlacedRepo>>{};
  for (final r in repos) {
    final parentExists = r.parentId != null && byId.containsKey(r.parentId);
    childRepos.putIfAbsent(parentExists ? r.parentId : null, () => []).add(r);
  }

  List<RepoTreeNode> nodesUnder(FolderId? parent) {
    final nodes = <RepoTreeNode>[
      for (final f in childFolders[parent] ?? const [])
        FolderNode(f, nodesUnder(f.id)),
      for (final r in childRepos[parent] ?? const [])
        RepoNode(r.location, r.sortOrder),
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return nodes;
  }

  return nodesUnder(null);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/application/workspaces/build_repo_tree_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/application/workspaces/repo_tree_node.dart lib/application/workspaces/build_repo_tree.dart test/application/workspaces/build_repo_tree_test.dart
git commit -m "feat(repos): pure buildRepoTree with orphan and cycle defenses"
```

---

### Task 4: `RepoTreeStore` port + Drift folder CRUD

**Files:**
- Create: `lib/application/workspaces/repo_tree_store.dart` (interface)
- Create: `lib/infrastructure/persistence/repo_tree_store_impl.dart`
- Test: `test/infrastructure/persistence/repo_tree_store_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `Folder`, `FolderId`, `RepoId`, `RepoLocation`, `PlacedRepo`.
- Produces — `abstract interface class RepoTreeStore`:
  - `Future<List<Folder>> loadFolders()`
  - `Future<List<PlacedRepo>> loadPlacedRepos()`
  - `Future<Folder> createFolder({required String name, FolderId? parentId})` — appended last in its parent's shared order.
  - `Future<void> renameFolder(FolderId id, String name)`
  - `Future<void> setCollapsed(FolderId id, bool collapsed)`
  - `Future<void> removeFolder(FolderId id)` — re-parents children (folders + repos) to the removed folder's parent, appended after existing siblings, then deletes the folder.
  - (move/reorder added in Task 5.)

- [ ] **Step 1: Write the failing test**

```dart
// test/infrastructure/persistence/repo_tree_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/infrastructure/persistence/repo_tree_store_impl.dart';
import 'package:gitopen/infrastructure/persistence/repository_registry_impl.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  group('DriftRepoTreeStore folder CRUD', () {
    test('createFolder persists and appends in parent order', () async {
      final db = newInMemoryDb();
      final sut = DriftRepoTreeStore(db);
      final a = await sut.createFolder(name: 'Work');
      final b = await sut.createFolder(name: 'Personal');
      final folders = await sut.loadFolders();
      expect(folders.map((f) => f.name), containsAll(['Work', 'Personal']));
      expect(a.sortOrder, 0);
      expect(b.sortOrder, 1);
      await db.close();
    });

    test('renameFolder and setCollapsed update the row', () async {
      final db = newInMemoryDb();
      final sut = DriftRepoTreeStore(db);
      final f = await sut.createFolder(name: 'Work');
      await sut.renameFolder(f.id, 'Job');
      await sut.setCollapsed(f.id, true);
      final loaded = (await sut.loadFolders()).single;
      expect(loaded.name, 'Job');
      expect(loaded.collapsed, isTrue);
      await db.close();
    });

    test('removeFolder re-parents children to the grandparent', () async {
      final db = newInMemoryDb();
      final registry = DriftRepositoryRegistry(db);
      final sut = DriftRepoTreeStore(db);
      final outer = await sut.createFolder(name: 'Outer');
      final inner = await sut.createFolder(name: 'Inner', parentId: outer.id);
      // Put a repo inside inner.
      final loc = await registry.add('/tmp/r');
      await sut.moveRepoForTest(loc.id, inner.id, 0); // helper defined in impl
      await sut.removeFolder(inner.id);
      final folders = await sut.loadFolders();
      expect(folders.map((f) => f.id), [outer.id]);
      final placed = await sut.loadPlacedRepos();
      expect(placed.single.parentId, outer.id); // moved up to outer
      await db.close();
    });
  });
}
```

> Note: `moveRepoForTest` stands in for the public `moveRepo` delivered in Task 5. To keep Task 4 self-contained, implement a minimal internal `_setRepoParent(repoId, parentId, sortOrder)` now and expose it as `moveRepoForTest`; Task 5 replaces the test call with the real `moveRepo` and removes the helper.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/infrastructure/persistence/repo_tree_store_test.dart`
Expected: FAIL — `DriftRepoTreeStore` does not exist.

- [ ] **Step 3: Write the interface**

```dart
// lib/application/workspaces/repo_tree_store.dart
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';

abstract interface class RepoTreeStore {
  Future<List<Folder>> loadFolders();
  Future<List<PlacedRepo>> loadPlacedRepos();
  Future<Folder> createFolder({required String name, FolderId? parentId});
  Future<void> renameFolder(FolderId id, String name);
  Future<void> setCollapsed(FolderId id, bool collapsed);
  Future<void> removeFolder(FolderId id);
}
```

- [ ] **Step 4: Write the Drift implementation (folder CRUD + loaders)**

```dart
// lib/infrastructure/persistence/repo_tree_store_impl.dart
import 'package:drift/drift.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/application/workspaces/repo_tree_store.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/persistence/database.dart';

final class DriftRepoTreeStore implements RepoTreeStore {
  DriftRepoTreeStore(this._db);
  final AppDatabase _db;

  @override
  Future<List<Folder>> loadFolders() async {
    final rows = await _db.select(_db.folders).get();
    return rows.map(_toFolder).toList();
  }

  @override
  Future<List<PlacedRepo>> loadPlacedRepos() async {
    final rows = await _db.select(_db.repositories).get();
    return rows
        .map((r) => PlacedRepo(
              location: RepoLocation(RepoId(r.id), r.path, r.displayName),
              parentId:
                  r.parentFolderId == null ? null : FolderId(r.parentFolderId!),
              sortOrder: r.tabOrder,
            ))
        .toList();
  }

  @override
  Future<Folder> createFolder({
    required String name,
    FolderId? parentId,
  }) async {
    final id = FolderId.newId();
    final order = await _nextOrderUnder(parentId);
    final now = DateTime.now().toUtc();
    await _db.into(_db.folders).insert(FoldersCompanion.insert(
          id: id.value,
          name: name,
          parentId: Value(parentId?.value),
          sortOrder: order,
          createdUtc: now,
        ));
    return Folder(
      id: id, name: name, parentId: parentId, sortOrder: order,
      collapsed: false,
    );
  }

  @override
  Future<void> renameFolder(FolderId id, String name) async {
    await (_db.update(_db.folders)..where((f) => f.id.equals(id.value)))
        .write(FoldersCompanion(name: Value(name)));
  }

  @override
  Future<void> setCollapsed(FolderId id, bool collapsed) async {
    await (_db.update(_db.folders)..where((f) => f.id.equals(id.value)))
        .write(FoldersCompanion(collapsed: Value(collapsed)));
  }

  @override
  Future<void> removeFolder(FolderId id) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.folders)
            ..where((f) => f.id.equals(id.value)))
          .getSingleOrNull();
      if (row == null) return;
      final grandparent = row.parentId; // String?
      var next = await _nextOrderUnder(
        grandparent == null ? null : FolderId(grandparent),
      );
      // Re-parent child folders.
      final childFolders = await (_db.select(_db.folders)
            ..where((f) => f.parentId.equals(id.value)))
          .get();
      for (final c in childFolders) {
        await (_db.update(_db.folders)..where((f) => f.id.equals(c.id))).write(
          FoldersCompanion(parentId: Value(grandparent), sortOrder: Value(next++)),
        );
      }
      // Re-parent child repos.
      final childRepos = await (_db.select(_db.repositories)
            ..where((r) => r.parentFolderId.equals(id.value)))
          .get();
      for (final c in childRepos) {
        await (_db.update(_db.repositories)..where((r) => r.id.equals(c.id)))
            .write(RepositoriesCompanion(
          parentFolderId: Value(grandparent),
          tabOrder: Value(next++),
        ));
      }
      await (_db.delete(_db.folders)..where((f) => f.id.equals(id.value))).go();
    });
  }

  // Test-only seam, replaced by public moveRepo in Task 5.
  Future<void> moveRepoForTest(RepoId repoId, FolderId? parent, int order) =>
      _setRepoParent(repoId, parent, order);

  Future<void> _setRepoParent(RepoId repoId, FolderId? parent, int order) async {
    await (_db.update(_db.repositories)..where((r) => r.id.equals(repoId.value)))
        .write(RepositoriesCompanion(
      parentFolderId: Value(parent?.value),
      tabOrder: Value(order),
    ));
  }

  Future<int> _nextOrderUnder(FolderId? parent) async {
    final folderMax = await _maxOrder(
      _db.select(_db.folders)
        ..where((f) => parent == null
            ? f.parentId.isNull()
            : f.parentId.equals(parent.value)),
      (f) => f.sortOrder,
    );
    final repoMax = await _maxOrder(
      _db.select(_db.repositories)
        ..where((r) => parent == null
            ? r.parentFolderId.isNull()
            : r.parentFolderId.equals(parent.value)),
      (r) => r.tabOrder,
    );
    final maxOrder = [folderMax, repoMax].whereType<int>().fold<int>(-1,
        (a, b) => a > b ? a : b);
    return maxOrder + 1;
  }

  Future<int?> _maxOrder<T extends DataClass>(
    Selectable<T> query,
    int Function(T) order,
  ) async {
    final rows = await query.get();
    if (rows.isEmpty) return null;
    return rows.map(order).reduce((a, b) => a > b ? a : b);
  }

  Folder _toFolder(FolderData r) => Folder(
        id: FolderId(r.id),
        name: r.name,
        parentId: r.parentId == null ? null : FolderId(r.parentId!),
        sortOrder: r.sortOrder,
        collapsed: r.collapsed,
      );
}
```

> `FolderData` / `FoldersCompanion` are Drift-generated from the `Folders` table (Task 2). If the generated row class name differs, use the name Drift emits (run codegen, then check `database.g.dart`).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/infrastructure/persistence/repo_tree_store_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/application/workspaces/repo_tree_store.dart lib/infrastructure/persistence/repo_tree_store_impl.dart test/infrastructure/persistence/repo_tree_store_test.dart
git commit -m "feat(repos): RepoTreeStore folder CRUD with non-destructive removal"
```

---

### Task 5: Move & reorder (shared sortOrder) + descendant guard

**Files:**
- Modify: `lib/application/workspaces/repo_tree_store.dart` (add move ops)
- Modify: `lib/infrastructure/persistence/repo_tree_store_impl.dart`
- Modify: `lib/infrastructure/persistence/repository_registry_impl.dart` (`add` appends at root using the shared next-order)
- Test: `test/infrastructure/persistence/repo_tree_store_move_test.dart`
- Test: edit `test/infrastructure/persistence/repo_tree_store_test.dart` (swap `moveRepoForTest` → `moveRepo`)

**Interfaces:**
- Produces — added to `RepoTreeStore`:
  - `Future<void> moveRepo(RepoId id, {FolderId? toParent, required int atIndex})`
  - `Future<void> moveFolder(FolderId id, {FolderId? toParent, required int atIndex})` — no-op if `toParent` is `id` or any descendant of `id`.
- Behavior: after any move the destination parent's children (folders + repos) are resequenced to a dense `0..n-1`; the moved node is inserted at `atIndex` (clamped).

- [ ] **Step 1: Write the failing test**

```dart
// test/infrastructure/persistence/repo_tree_store_move_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/workspaces/build_repo_tree.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/infrastructure/persistence/repo_tree_store_impl.dart';
import 'package:gitopen/infrastructure/persistence/repository_registry_impl.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  group('DriftRepoTreeStore move/reorder', () {
    test('moveRepo into a folder at index resequences siblings densely',
        () async {
      final db = newInMemoryDb();
      final registry = DriftRepositoryRegistry(db);
      final store = DriftRepoTreeStore(db);
      final work = await store.createFolder(name: 'Work');
      final a = await registry.add('/tmp/a');
      final b = await registry.add('/tmp/b');
      await store.moveRepo(a.id, toParent: work.id, atIndex: 0);
      await store.moveRepo(b.id, toParent: work.id, atIndex: 0); // b before a
      final tree = buildRepoTree(
        await store.loadFolders(), await store.loadPlacedRepos());
      final children = (tree.single as FolderNode).children;
      expect(children.map((n) => (n as RepoNode).location.path),
          ['/tmp/b', '/tmp/a']);
      expect(children.map((n) => n.sortOrder), [0, 1]); // dense
      await db.close();
    });

    test('moveFolder onto its own descendant is a no-op', () async {
      final db = newInMemoryDb();
      final store = DriftRepoTreeStore(db);
      final outer = await store.createFolder(name: 'Outer');
      final inner = await store.createFolder(name: 'Inner', parentId: outer.id);
      await store.moveFolder(outer.id, toParent: inner.id, atIndex: 0);
      final folders = await store.loadFolders();
      final outerRow = folders.firstWhere((f) => f.id == outer.id);
      expect(outerRow.parentId, isNull); // unchanged
      await db.close();
    });

    test('moveFolder reparents and resequences destination', () async {
      final db = newInMemoryDb();
      final store = DriftRepoTreeStore(db);
      final a = await store.createFolder(name: 'A');
      final b = await store.createFolder(name: 'B');
      await store.moveFolder(b.id, toParent: a.id, atIndex: 0);
      final folders = await store.loadFolders();
      expect(folders.firstWhere((f) => f.id == b.id).parentId, a.id);
      await db.close();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/infrastructure/persistence/repo_tree_store_move_test.dart`
Expected: FAIL — `moveRepo` / `moveFolder` not defined.

- [ ] **Step 3: Add move ops to the interface**

```dart
// add to lib/application/workspaces/repo_tree_store.dart
  Future<void> moveRepo(RepoId id, {FolderId? toParent, required int atIndex});
  Future<void> moveFolder(FolderId id, {FolderId? toParent, required int atIndex});
```
(Add `import 'package:gitopen/domain/repositories/repo_id.dart';` to the interface file.)

- [ ] **Step 4: Implement move ops + resequencing**

Replace the test-only seam with real ops in `repo_tree_store_impl.dart`. Remove `moveRepoForTest` and `_setRepoParent`; add:

```dart
  @override
  Future<void> moveRepo(
    RepoId id, {
    FolderId? toParent,
    required int atIndex,
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.repositories)..where((r) => r.id.equals(id.value)))
          .write(RepositoriesCompanion(parentFolderId: Value(toParent?.value)));
      await _resequence(toParent, moved: _MovedRef.repo(id), atIndex: atIndex);
    });
  }

  @override
  Future<void> moveFolder(
    FolderId id, {
    FolderId? toParent,
    required int atIndex,
  }) async {
    if (await _wouldCycle(id, toParent)) return;
    await _db.transaction(() async {
      await (_db.update(_db.folders)..where((f) => f.id.equals(id.value)))
          .write(FoldersCompanion(parentId: Value(toParent?.value)));
      await _resequence(toParent, moved: _MovedRef.folder(id), atIndex: atIndex);
    });
  }

  /// True if [toParent] is [id] itself or any descendant of [id].
  Future<bool> _wouldCycle(FolderId id, FolderId? toParent) async {
    if (toParent == null) return false;
    if (toParent == id) return true;
    final all = await loadFolders();
    final byId = {for (final f in all) f.id: f};
    var cursor = toParent;
    final seen = <FolderId>{};
    while (true) {
      if (cursor == id) return true;
      if (!seen.add(cursor)) return false; // pre-existing loop, bail safely
      final parent = byId[cursor]?.parentId;
      if (parent == null) return false;
      cursor = parent;
    }
  }

  /// Rewrites the dense 0..n-1 order of [parent]'s children, placing [moved]
  /// at [atIndex] (clamped). Children are ordered by current sortOrder, with
  /// the moved node extracted first.
  Future<void> _resequence(
    FolderId? parent, {
    required _MovedRef moved,
    required int atIndex,
  }) async {
    final folders = await (_db.select(_db.folders)
          ..where((f) => parent == null
              ? f.parentId.isNull()
              : f.parentId.equals(parent.value)))
        .get();
    final repos = await (_db.select(_db.repositories)
          ..where((r) => parent == null
              ? r.parentFolderId.isNull()
              : r.parentFolderId.equals(parent.value)))
        .get();

    final siblings = <_MovedRef>[
      for (final f in folders) _MovedRef.folder(FolderId(f.id)).withOrder(f.sortOrder),
      for (final r in repos) _MovedRef.repo(RepoId(r.id)).withOrder(r.tabOrder),
    ]..sort((a, b) => a.order.compareTo(b.order));

    siblings.removeWhere((s) => s.sameTarget(moved));
    final index = atIndex.clamp(0, siblings.length);
    siblings.insert(index, moved);

    for (var i = 0; i < siblings.length; i++) {
      final s = siblings[i];
      if (s.isFolder) {
        await (_db.update(_db.folders)..where((f) => f.id.equals(s.folderId!.value)))
            .write(FoldersCompanion(sortOrder: Value(i)));
      } else {
        await (_db.update(_db.repositories)..where((r) => r.id.equals(s.repoId!.value)))
            .write(RepositoriesCompanion(tabOrder: Value(i)));
      }
    }
  }
```

Add the small ref helper at the bottom of the file:

```dart
class _MovedRef {
  _MovedRef.folder(this.folderId) : repoId = null, order = 0;
  _MovedRef.repo(this.repoId) : folderId = null, order = 0;
  final FolderId? folderId;
  final RepoId? repoId;
  int order;

  bool get isFolder => folderId != null;
  _MovedRef withOrder(int o) => this..order = o;
  bool sameTarget(_MovedRef other) =>
      isFolder ? folderId == other.folderId : repoId == other.repoId;
}
```

(Add `import 'package:gitopen/domain/repositories/repo_id.dart';` to the impl if not already present.)

- [ ] **Step 5: Update the Task-4 test to use the real `moveRepo`**

In `test/infrastructure/persistence/repo_tree_store_test.dart`, replace
`await sut.moveRepoForTest(loc.id, inner.id, 0);` with
`await sut.moveRepo(loc.id, toParent: inner.id, atIndex: 0);`.

- [ ] **Step 6: Make `registry.add` append at the shared root order**

In `repository_registry_impl.dart`, replace the `tabOrder: count` insert so new repos land after existing root children:

```dart
  @override
  Future<RepoLocation> add(String path) async {
    final existing = await (_db.select(_db.repositories)
          ..where((r) => r.path.equals(path)))
        .getSingleOrNull();
    if (existing != null) {
      return RepoLocation(RepoId(existing.id), existing.path, existing.displayName);
    }
    final id = RepoId.newId();
    final now = DateTime.now().toUtc();
    await _db.into(_db.repositories).insert(RepositoriesCompanion.insert(
          id: id.value,
          path: path,
          displayName: _displayName(path),
          lastOpenedUtc: now,
          tabOrder: await _nextRootOrder(),
          createdUtc: now,
        ));
    return RepoLocation(id, path, _displayName(path));
  }

  Future<int> _nextRootOrder() async {
    final folders = await (_db.select(_db.folders)
          ..where((f) => f.parentId.isNull()))
        .get();
    final repos = await (_db.select(_db.repositories)
          ..where((r) => r.parentFolderId.isNull()))
        .get();
    final orders = [
      ...folders.map((f) => f.sortOrder),
      ...repos.map((r) => r.tabOrder),
    ];
    return orders.isEmpty ? 0 : (orders.reduce((a, b) => a > b ? a : b) + 1);
  }
```

- [ ] **Step 7: Run the tests**

Run: `flutter test test/infrastructure/persistence/`
Expected: PASS — move/reorder, folder CRUD, registry, migration suites all green.

- [ ] **Step 8: Commit**

```bash
git add lib/application/workspaces/repo_tree_store.dart lib/infrastructure/persistence/repo_tree_store_impl.dart lib/infrastructure/persistence/repository_registry_impl.dart test/infrastructure/persistence/repo_tree_store_test.dart test/infrastructure/persistence/repo_tree_store_move_test.dart
git commit -m "feat(repos): move/reorder repos and folders in a shared sort space"
```

---

### Task 6: `WorkspaceManager` becomes catalog-backed; `remove` replaces `close`

**Files:**
- Modify: `lib/application/workspaces/workspace_manager.dart`
- Test: `test/application/workspaces/workspace_manager_test.dart` (update `close` → `remove`, add load-all)

**Interfaces:**
- Consumes: `RepositoryRegistry`.
- Produces — `WorkspaceManager`:
  - `Future<void> loadAll()` — populates state from `registry.list()`.
  - `Future<Workspace> open(String path)` — unchanged add-if-new + touch; returns workspace.
  - `Future<void> remove(RepoId id)` — `registry.remove(id)` then drop from state.
  - keeps `find(RepoId)`. The old `close` and `reorder` are removed.

- [ ] **Step 1: Update the failing test**

```dart
// test/application/workspaces/workspace_manager_test.dart  (replace close test + add loadAll)
    test('loadAll populates state from the registry', () async {
      final registry = _FakeRegistry();
      await registry.add('/x');
      await registry.add('/y');
      final sut = WorkspaceManager(registry);
      await sut.loadAll();
      expect(sut.state, hasLength(2));
    });

    test('remove deletes from the registry and state', () async {
      final registry = _FakeRegistry();
      final sut = WorkspaceManager(registry);
      final ws = await sut.open('/x');
      await sut.remove(ws.location.id);
      expect(sut.state, isEmpty);
      expect(await registry.list(), isEmpty);
    });
```

(Delete the old `close removes the workspace` test.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/application/workspaces/workspace_manager_test.dart`
Expected: FAIL — `loadAll` / `remove` not defined.

- [ ] **Step 3: Update `WorkspaceManager`**

```dart
// lib/application/workspaces/workspace_manager.dart
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/workspaces/repository_registry.dart';
import 'package:gitopen/application/workspaces/workspace.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';

final class WorkspaceManager extends StateNotifier<List<Workspace>> {
  WorkspaceManager(this._registry) : super(const []);
  final RepositoryRegistry _registry;

  /// Loads the full catalog from the registry. Called once at startup.
  Future<void> loadAll() async {
    final locations = await _registry.list();
    state = [for (final loc in locations) Workspace(loc)];
  }

  Future<Workspace> open(String path) async {
    final loc = await _registry.add(path);
    final existing = state.firstWhereOrNull((w) => w.location.id == loc.id);
    if (existing != null) return existing;
    final ws = Workspace(loc);
    state = [...state, ws];
    await _registry.touchLastOpened(loc.id);
    return ws;
  }

  Future<void> remove(RepoId id) async {
    await _registry.remove(id);
    state = state.where((w) => w.location.id != id).toList(growable: false);
  }

  Workspace? find(RepoId id) =>
      state.firstWhereOrNull((w) => w.location.id == id);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/application/workspaces/workspace_manager_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/application/workspaces/workspace_manager.dart test/application/workspaces/workspace_manager_test.dart
git commit -m "feat(repos): WorkspaceManager loads full catalog; remove replaces close"
```

---

### Task 7: `RepoOrganizer` notifier + providers

**Files:**
- Create: `lib/application/workspaces/repo_organizer.dart`
- Modify: `lib/application/providers.dart`
- Test: `test/application/workspaces/repo_organizer_test.dart`

**Interfaces:**
- Consumes: `RepoTreeStore`, `WorkspaceManager`.
- Produces:
  - `RepoOrganizer extends StateNotifier<List<RepoTreeNode>>`:
    - `Future<void> refresh()` — reloads folders + placed repos, rebuilds tree into state.
    - `Future<FolderId> createFolder(String name, {FolderId? parentId})`
    - `Future<void> renameFolder(FolderId, String)`, `Future<void> removeFolder(FolderId)`
    - `Future<void> setCollapsed(FolderId, bool)`
    - `Future<void> moveRepo(RepoId, {FolderId? toParent, required int atIndex})`
    - `Future<void> moveFolder(FolderId, {FolderId? toParent, required int atIndex})`
    - each mutation calls the store then `refresh()`; on store error, calls `refresh()` and rethrows so the UI can show a SnackBar.
  - Providers: `repoTreeStoreProvider`, `repoOrganizerProvider`.

- [ ] **Step 1: Write the failing test**

```dart
// test/application/workspaces/repo_organizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/workspaces/build_repo_tree.dart';
import 'package:gitopen/application/workspaces/repo_organizer.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/application/workspaces/repo_tree_store.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';

class _FakeStore implements RepoTreeStore {
  final List<Folder> folders = [];
  final List<PlacedRepo> repos = [];
  int _order = 0;

  @override
  Future<List<Folder>> loadFolders() async => List.of(folders);
  @override
  Future<List<PlacedRepo>> loadPlacedRepos() async => List.of(repos);

  @override
  Future<Folder> createFolder({required String name, FolderId? parentId}) async {
    final f = Folder(
      id: FolderId.newId(), name: name, parentId: parentId,
      sortOrder: _order++, collapsed: false,
    );
    folders.add(f);
    return f;
  }

  @override
  Future<void> renameFolder(FolderId id, String name) async {}
  @override
  Future<void> setCollapsed(FolderId id, bool collapsed) async {}
  @override
  Future<void> removeFolder(FolderId id) async {
    folders.removeWhere((f) => f.id == id);
  }
  @override
  Future<void> moveRepo(RepoId id, {FolderId? toParent, required int atIndex}) async {}
  @override
  Future<void> moveFolder(FolderId id, {FolderId? toParent, required int atIndex}) async {}
}

void main() {
  test('createFolder refreshes the tree state', () async {
    final store = _FakeStore();
    final sut = RepoOrganizer(store);
    await sut.refresh();
    expect(sut.state, isEmpty);
    await sut.createFolder('Work');
    expect(sut.state, hasLength(1));
    expect((sut.state.single as FolderNode).folder.name, 'Work');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/application/workspaces/repo_organizer_test.dart`
Expected: FAIL — `RepoOrganizer` not defined.

- [ ] **Step 3: Write `RepoOrganizer`**

```dart
// lib/application/workspaces/repo_organizer.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/workspaces/build_repo_tree.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/application/workspaces/repo_tree_store.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';

final class RepoOrganizer extends StateNotifier<List<RepoTreeNode>> {
  RepoOrganizer(this._store) : super(const []);
  final RepoTreeStore _store;

  Future<void> refresh() async {
    final folders = await _store.loadFolders();
    final repos = await _store.loadPlacedRepos();
    state = buildRepoTree(folders, repos);
  }

  Future<FolderId> createFolder(String name, {FolderId? parentId}) async {
    final folder = await _store.createFolder(name: name, parentId: parentId);
    await refresh();
    return folder.id;
  }

  Future<void> renameFolder(FolderId id, String name) =>
      _mutate(() => _store.renameFolder(id, name));
  Future<void> removeFolder(FolderId id) =>
      _mutate(() => _store.removeFolder(id));
  Future<void> setCollapsed(FolderId id, bool collapsed) =>
      _mutate(() => _store.setCollapsed(id, collapsed));
  Future<void> moveRepo(RepoId id, {FolderId? toParent, required int atIndex}) =>
      _mutate(() => _store.moveRepo(id, toParent: toParent, atIndex: atIndex));
  Future<void> moveFolder(FolderId id, {FolderId? toParent, required int atIndex}) =>
      _mutate(() => _store.moveFolder(id, toParent: toParent, atIndex: atIndex));

  Future<void> _mutate(Future<void> Function() op) async {
    try {
      await op();
    } finally {
      await refresh(); // reload truth even if the op threw
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/application/workspaces/repo_organizer_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire providers**

In `lib/application/providers.dart` add (near `workspaceManagerProvider`):

```dart
import 'package:gitopen/application/workspaces/repo_organizer.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/application/workspaces/repo_tree_store.dart';
import 'package:gitopen/infrastructure/persistence/repo_tree_store_impl.dart';
// ...
final repoTreeStoreProvider = Provider<RepoTreeStore>((ref) {
  return DriftRepoTreeStore(ref.watch(appDatabaseProvider));
});

final repoOrganizerProvider =
    StateNotifierProvider<RepoOrganizer, List<RepoTreeNode>>((ref) {
  return RepoOrganizer(ref.watch(repoTreeStoreProvider));
});
```

- [ ] **Step 6: Run analyzer + full provider deps compile**

Run: `flutter analyze lib/application`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/application/workspaces/repo_organizer.dart lib/application/providers.dart test/application/workspaces/repo_organizer_test.dart
git commit -m "feat(repos): RepoOrganizer notifier and providers for the repo tree"
```

---

### Task 8: Startup rehydrate + `last_active_repo`; retire `open_workspaces`

**Files:**
- Modify: `lib/main.dart` (`_rehydrate`, `_subscribePersistence`)
- Modify: `lib/application/workspaces/workspace_persistence.dart` (replace open-paths with last-active)
- Modify: `lib/infrastructure/persistence/workspace_persistence_impl.dart`
- Test: `test/infrastructure/persistence/workspace_persistence_test.dart` (update to last-active)

**Interfaces:**
- Produces — `WorkspacePersistence`:
  - `Future<String?> getLastActiveRepoId()`
  - `Future<void> saveLastActiveRepoId(String? id)`
  (the `getOpenPaths`/`saveOpenPaths` pair is removed.)

- [ ] **Step 1: Update the failing persistence test**

```dart
// test/infrastructure/persistence/workspace_persistence_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/persistence/workspace_persistence_impl.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  group('DriftWorkspacePersistence', () {
    test('round-trips the last active repo id', () async {
      final db = newInMemoryDb();
      final sut = DriftWorkspacePersistence(db);
      expect(await sut.getLastActiveRepoId(), isNull);
      await sut.saveLastActiveRepoId('abc123');
      expect(await sut.getLastActiveRepoId(), 'abc123');
      await sut.saveLastActiveRepoId(null);
      expect(await sut.getLastActiveRepoId(), isNull);
      await db.close();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/infrastructure/persistence/workspace_persistence_test.dart`
Expected: FAIL — `getLastActiveRepoId` not defined.

- [ ] **Step 3: Update the interface**

```dart
// lib/application/workspaces/workspace_persistence.dart
abstract interface class WorkspacePersistence {
  Future<String?> getLastActiveRepoId();
  Future<void> saveLastActiveRepoId(String? id);
}
```

- [ ] **Step 4: Update the Drift impl**

```dart
// lib/infrastructure/persistence/workspace_persistence_impl.dart
import 'dart:convert';
import 'package:gitopen/application/workspaces/workspace_persistence.dart';
import 'package:gitopen/infrastructure/persistence/database.dart';

const String _key = 'last_active_repo';

final class DriftWorkspacePersistence implements WorkspacePersistence {
  DriftWorkspacePersistence(this._db);
  final AppDatabase _db;

  @override
  Future<String?> getLastActiveRepoId() async {
    final row = await (_db.select(_db.settings)
          ..where((s) => s.key.equals(_key)))
        .getSingleOrNull();
    if (row == null) return null;
    final decoded = jsonDecode(row.valueJson);
    return decoded is String ? decoded : null;
  }

  @override
  Future<void> saveLastActiveRepoId(String? id) async {
    await _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: _key, valueJson: jsonEncode(id)),
        );
  }
}
```

- [ ] **Step 5: Update `main.dart` rehydrate + persistence subscription**

```dart
// lib/main.dart  — replace _rehydrate body
Future<void> _rehydrate(ProviderContainer container) async {
  try {
    final manager = container.read(workspaceManagerProvider.notifier);
    await manager.loadAll();
    await container.read(repoOrganizerProvider.notifier).refresh();

    final persistence = container.read(workspacePersistenceProvider);
    final lastId = await persistence.getLastActiveRepoId();
    final workspaces = container.read(workspaceManagerProvider);
    final restored = workspaces
        .where((w) => w.location.id.value == lastId)
        .map((w) => w.location.id)
        .firstOrNull;
    container.read(activeWorkspaceIdProvider.notifier).state =
        restored ?? (workspaces.isEmpty ? null : workspaces.first.location.id);
  } on Object catch (e) {
    _log.w('Rehydration failed: $e');
  }
}
```

```dart
// lib/main.dart  — replace _subscribePersistence body
void _subscribePersistence(ProviderContainer container) {
  container.listen<RepoId?>(activeWorkspaceIdProvider, (previous, next) async {
    final persistence = container.read(workspacePersistenceProvider);
    try {
      await persistence.saveLastActiveRepoId(next?.value);
    } on Object catch (e) {
      _log.w('Persist active repo failed: $e');
    }
  });
}
```

Add imports to `main.dart` if missing: `repo_organizer.dart` provider is in `providers.dart` (already imported); `RepoId` from `domain/repositories/repo_id.dart`; `firstOrNull` comes from `package:collection/collection.dart`. Remove the now-unused `Workspace` import only if the analyzer flags it.

- [ ] **Step 6: Update `repo_selector.dart` callers that used `close`**

The dropdown is replaced wholesale in Task 9, but until then keep `main.dart` compiling: the `_subscribePersistence` previously listened to `workspaceManagerProvider`; it now listens to `activeWorkspaceIdProvider`. Ensure no remaining references to `getOpenPaths`/`saveOpenPaths`/`manager.close`/`manager.reorder` exist:

Run: `grep -rn "getOpenPaths\|saveOpenPaths\|\.close(\|\.reorder(" lib --include=*.dart`
Expected (before Task 9): only `repo_selector.dart` references `manager.close` — temporarily change its `_close` to call `manager.remove` so the app compiles; Task 9 removes that method entirely.

- [ ] **Step 7: Run tests + analyze**

Run: `flutter test test/infrastructure/persistence/workspace_persistence_test.dart && flutter analyze lib`
Expected: test PASS; analyzer clean (or only pre-existing warnings).

- [ ] **Step 8: Commit**

```bash
git add lib/main.dart lib/application/workspaces/workspace_persistence.dart lib/infrastructure/persistence/workspace_persistence_impl.dart lib/ui/shell/repo_selector.dart test/infrastructure/persistence/workspace_persistence_test.dart
git commit -m "feat(repos): catalog rehydrate and last-active-repo persistence"
```

---

### Task 9: Tree popover UI — render, collapse, select (no drag yet)

**Files:**
- Create: `lib/ui/shell/repo_tree_popover.dart`
- Create: `lib/ui/shell/repo_tree_row.dart` (folder row + repo row widgets)
- Modify: `lib/ui/shell/repo_selector.dart` (button opens the popover; remove `MenuAnchor` body and the old `close`/folder-scan menu items, re-add them inside the popover footer)
- Test: `test/ui/shell/repo_tree_popover_test.dart`

**Interfaces:**
- Consumes: `repoOrganizerProvider`, `activeWorkspaceIdProvider`, `RepoTreeNode`/`FolderNode`/`RepoNode`, `AppPalette`, `folderPickerProvider`, `repoFolderScannerProvider`, `workspaceManagerProvider`.
- Produces:
  - `flattenVisible(List<RepoTreeNode> roots) -> List<VisibleRow>` — pre-order walk; a collapsed `FolderNode` contributes its own row but not its descendants. `VisibleRow` = `{RepoTreeNode node, int depth}`.
  - `RepoTreePopover` widget rendering the flattened rows.

- [ ] **Step 1: Write the failing widget/unit test**

```dart
// test/ui/shell/repo_tree_popover_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/shell/repo_tree_popover.dart';

void main() {
  group('flattenVisible', () {
    test('hides descendants of a collapsed folder', () {
      final repo = RepoNode(RepoLocation(RepoId('r'), '/p/r', 'r'), 0);
      final collapsed = FolderNode(
        const Folder(
          id: FolderId('f'), name: 'Work', parentId: null,
          sortOrder: 0, collapsed: true,
        ),
        [repo],
      );
      final rows = flattenVisible([collapsed]);
      expect(rows, hasLength(1)); // folder only, child hidden
      expect((rows.single.node as FolderNode).folder.name, 'Work');
    });

    test('shows descendants of an expanded folder with depth', () {
      final repo = RepoNode(RepoLocation(RepoId('r'), '/p/r', 'r'), 0);
      final expanded = FolderNode(
        const Folder(
          id: FolderId('f'), name: 'Work', parentId: null,
          sortOrder: 0, collapsed: false,
        ),
        [repo],
      );
      final rows = flattenVisible([expanded]);
      expect(rows, hasLength(2));
      expect(rows[0].depth, 0);
      expect(rows[1].depth, 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/shell/repo_tree_popover_test.dart`
Expected: FAIL — `flattenVisible` not defined.

- [ ] **Step 3: Implement `flattenVisible` + `VisibleRow`**

```dart
// lib/ui/shell/repo_tree_popover.dart  (top of file; widget added in Step 4)
import 'package:gitopen/application/workspaces/repo_tree_node.dart';

class VisibleRow {
  const VisibleRow(this.node, this.depth);
  final RepoTreeNode node;
  final int depth;
}

List<VisibleRow> flattenVisible(List<RepoTreeNode> roots) {
  final out = <VisibleRow>[];
  void walk(List<RepoTreeNode> nodes, int depth) {
    for (final n in nodes) {
      out.add(VisibleRow(n, depth));
      if (n is FolderNode && !n.folder.collapsed) {
        walk(n.children, depth + 1);
      }
    }
  }
  walk(roots, 0);
  return out;
}
```

- [ ] **Step 4: Implement the popover widget + rows**

Build `RepoTreePopover` as a `ConsumerWidget` that watches `repoOrganizerProvider` and renders `flattenVisible(...)` in a scrollable `Column`/`ListView` inside a sized container styled with `AppPalette` (reuse the `bg2`/`border`/hover colors from the existing `repo_selector.dart`). Each row:

```dart
// lib/ui/shell/repo_tree_row.dart  (folder + repo rows)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/repo_organizer.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class FolderRow extends ConsumerWidget {
  const FolderRow({required this.folder, required this.depth, super.key});
  final Folder folder;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: () => ref
          .read(repoOrganizerProvider.notifier)
          .setCollapsed(folder.id, !folder.collapsed),
      child: Padding(
        padding: EdgeInsets.only(left: 12.0 + depth * 16, right: 12,
            top: 6, bottom: 6),
        child: Row(children: [
          Icon(folder.collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 16, color: palette.fg2),
          const SizedBox(width: 6),
          Icon(Icons.folder, size: 15, color: palette.fg1),
          const SizedBox(width: 8),
          Expanded(child: Text(folder.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.fg0, fontSize: 12.5,
                  fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}

class RepoRow extends ConsumerWidget {
  const RepoRow({
    required this.location,
    required this.depth,
    required this.isActive,
    required this.onSelect,
    super.key,
  });
  final RepoLocation location;
  final int depth;
  final bool isActive;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onSelect,
      child: Padding(
        padding: EdgeInsets.only(left: 12.0 + depth * 16, right: 8,
            top: 6, bottom: 6),
        child: Row(children: [
          SizedBox(width: 14, child: isActive
              ? Icon(Icons.check, size: 14, color: palette.accentCurrent)
              : null),
          const SizedBox(width: 6),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(location.displayName, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: isActive ? palette.fg0 : palette.fg1,
                      fontSize: 12.5)),
              Text(location.path, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.fg3, fontSize: 11)),
            ],
          )),
          _RowMenu(location: location),
        ]),
      ),
    );
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.location});
  final RepoLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: 16, color: palette.fg2),
      tooltip: 'Repository actions',
      onSelected: (value) async {
        if (value == 'remove') {
          final active = ref.read(activeWorkspaceIdProvider);
          await ref.read(workspaceManagerProvider.notifier)
              .remove(location.id);
          await ref.read(repoOrganizerProvider.notifier).refresh();
          if (active == location.id) {
            final remaining = ref.read(workspaceManagerProvider);
            ref.read(activeWorkspaceIdProvider.notifier).state =
                remaining.isEmpty ? null : remaining.first.location.id;
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'remove', child: Text('Remove from GitOpen')),
      ],
    );
  }
}
```

The `RepoTreePopover` maps each `VisibleRow` to `FolderRow` or `RepoRow` (passing `isActive = row.node is RepoNode && node.location.id == activeId`, and `onSelect` sets `activeWorkspaceIdProvider`). Footer `Row`/`Column` reuses the existing "New folder" (inline `TextField` → `repoOrganizerProvider.notifier.createFolder`), "Open repository…", "Open folder of repos…", and "Clone…" actions lifted from the current `repo_selector.dart`.

- [ ] **Step 5: Swap the selector body to open the popover**

In `repo_selector.dart`, keep `_SelectorButton`; replace the `MenuAnchor` with an `OverlayPortal` (or `showMenu`-free custom overlay) that toggles `RepoTreePopover` anchored under the button, dismissing on outside tap / `Esc`. Delete `_RepoMenuItem`, `_close`, `_openRepo`/`_openReposFolder`/`_cloneRepo` (moved into the popover footer). The button label still reads the active workspace name via `workspaceManagerProvider` + `activeWorkspaceIdProvider`.

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/ui/shell/repo_tree_popover_test.dart && flutter analyze lib/ui/shell`
Expected: PASS; analyzer clean.

- [ ] **Step 7: Manual smoke**

Run: `flutter run -d windows`
Confirm: dropdown shows the tree; folders expand/collapse; selecting a repo switches the active view; "New folder" creates a folder; "Remove from GitOpen" forgets a repo; restart preserves folders + active repo.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/shell/repo_tree_popover.dart lib/ui/shell/repo_tree_row.dart lib/ui/shell/repo_selector.dart test/ui/shell/repo_tree_popover_test.dart
git commit -m "feat(repos): tree popover with collapse, select, and folder actions"
```

---

### Task 10: Drag & drop — move repos and folders

**Files:**
- Create: `lib/ui/shell/repo_tree_drag.dart` (drag payload + drop-target helpers)
- Modify: `lib/ui/shell/repo_tree_popover.dart` (wrap rows in `Draggable`/`DragTarget`)
- Modify: `lib/ui/shell/repo_tree_row.dart` (add a drag handle affordance)
- Test: `test/ui/shell/repo_tree_drag_test.dart`

**Interfaces:**
- Produces:
  - `sealed class DragRef { }` → `RepoDragRef(RepoId)` | `FolderDragRef(FolderId)`.
  - `DropTarget` resolver: given a hovered `VisibleRow` and a vertical position (top-half / bottom-half / onto-folder-label), compute `(FolderId? parent, int atIndex)` and dispatch to `repoOrganizerProvider.notifier.moveRepo`/`moveFolder`.

- [ ] **Step 1: Write the failing test (drop-intent math, pure)**

```dart
// test/ui/shell/repo_tree_drag_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/shell/repo_tree_drag.dart';

void main() {
  group('resolveDropIndex', () {
    test('top half inserts before the hovered index', () {
      expect(resolveDropIndex(hoveredIndex: 3, isTopHalf: true), 3);
    });
    test('bottom half inserts after the hovered index', () {
      expect(resolveDropIndex(hoveredIndex: 3, isTopHalf: false), 4);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/shell/repo_tree_drag_test.dart`
Expected: FAIL — `resolveDropIndex` not defined.

- [ ] **Step 3: Implement the drag payloads + index math**

```dart
// lib/ui/shell/repo_tree_drag.dart
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';

sealed class DragRef {
  const DragRef();
}

final class RepoDragRef extends DragRef {
  const RepoDragRef(this.id);
  final RepoId id;
}

final class FolderDragRef extends DragRef {
  const FolderDragRef(this.id);
  final FolderId id;
}

/// Index within a parent's child list where a node dropped over
/// [hoveredIndex] should land: before it (top half) or after it (bottom half).
int resolveDropIndex({required int hoveredIndex, required bool isTopHalf}) {
  return isTopHalf ? hoveredIndex : hoveredIndex + 1;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/shell/repo_tree_drag_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire drag & drop into the popover**

Wrap each rendered row in a `Draggable<DragRef>` (feedback = a faded row clone; the row keeps a visible drag handle via `Icons.drag_indicator`). Overlay each row with a `DragTarget<DragRef>`:
- `onWillAcceptWithDetails`: reject when the payload is the row's own node; compute top/bottom half from `details.offset` relative to the row box.
- `onAcceptWithDetails`: for a hovered `RepoNode` → drop is a sibling insertion: `parent = node's parent folder id` (track the parent during flatten by extending `VisibleRow` with `parentId`), `atIndex = resolveDropIndex(hoveredSiblingIndex, isTopHalf)`. For a hovered `FolderNode` label centre-zone → drop **into** the folder at index 0 (`parent = folder.id, atIndex = 0`).
- Dispatch: `RepoDragRef` → `moveRepo(id, toParent: parent, atIndex: idx)`; `FolderDragRef` → `moveFolder(id, toParent: parent, atIndex: idx)` (the store already rejects descendant drops, so the UI need not duplicate the cycle check, but it should still skip the obvious self-drop).

Extend `flattenVisible` to also record each row's `parentId` (the enclosing `FolderNode.folder.id`, or null at root) and the row's `indexWithinParent`, so the drop handler can compute sibling indices without re-walking the tree. Update the Task-9 `VisibleRow` and its test accordingly (add `parentId`/`indexInParent`, default-checked in the existing tests).

- [ ] **Step 6: Add a widget test for a simulated reorder**

```dart
// append to test/ui/shell/repo_tree_drag_test.dart  (widget-level)
// Pump a RepoTreePopover with a fake RepoOrganizer exposing two root repos,
// perform a drag from row 0 to below row 1 via WidgetTester.drag, and assert
// the fake organizer recorded a moveRepo(atIndex: ...) call. Use a
// ProviderScope override for repoOrganizerProvider with a recording fake
// (mirror the _FakeStore pattern from repo_organizer_test.dart).
```

Implement that widget test concretely against the fake organizer (record `moveRepo`/`moveFolder` invocations), pump with `ProviderScope(overrides: [...])`, `await tester.drag(find.byKey(...), const Offset(0, 48))`, `await tester.pumpAndSettle()`, then assert the recorded call.

- [ ] **Step 7: Run tests + analyze**

Run: `flutter test test/ui/shell/ && flutter analyze lib/ui/shell`
Expected: PASS; analyzer clean.

- [ ] **Step 8: Manual smoke**

Run: `flutter run -d windows`
Confirm: drag a repo within a folder, across folders, and to root; drag a folder to reorder and to reparent; dragging a folder onto its own descendant does nothing; order survives restart.

- [ ] **Step 9: Commit**

```bash
git add lib/ui/shell/repo_tree_drag.dart lib/ui/shell/repo_tree_popover.dart lib/ui/shell/repo_tree_row.dart test/ui/shell/repo_tree_drag_test.dart
git commit -m "feat(repos): drag and drop to reorder and reparent repos and folders"
```

---

### Task 11: Version bump + full verification

**Files:**
- Modify: `pubspec.yaml` (version bump so CD publishes)
- Modify: `CHANGELOG.md` (add the feature entry)

**Interfaces:** none.

- [ ] **Step 1: Bump the version**

In `pubspec.yaml`, bump `version:` (e.g. `1.0.3+xx` → next patch/minor `1.1.0+xx`, matching the repo's scheme — check the current value and increment the build number too).

- [ ] **Step 2: Add a CHANGELOG entry**

Add a top entry summarizing: "Repositories can be organized into nested folders and reordered by drag & drop; the dropdown is now a persistent catalog with a single active repo restored on launch."

- [ ] **Step 3: Run the full suite + analyzer**

Run: `flutter analyze && flutter test`
Expected: analyzer clean; **all** tests PASS (new suites + the existing ~unchanged suites).

- [ ] **Step 4: Grep for retired symbols**

Run: `grep -rn "getOpenPaths\|saveOpenPaths\|open_workspaces\|\.reorder(\|manager.close" lib --include=*.dart`
Expected: no matches (all retired).

- [ ] **Step 5: Final manual smoke (clean profile)**

Delete (or rename) the local state DB, launch fresh, confirm: empty catalog → welcome screen; open/clone adds repos at root; create nested folders; drag repos/folders; restart restores the tree + active repo. Then launch against the pre-existing DB (the v2→v3 upgrade path) and confirm existing repos appear at root in their prior order.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "chore(repos): bump version and changelog for folders & reordering"
```

---

## Self-Review

**Spec coverage:**
- Persistent catalog model → Tasks 6, 8 (load-all, last-active restore). ✓
- Nested folders / tree → Tasks 1–3 (model + buildRepoTree). ✓
- Reorder repos *and* folders, shared sort space → Task 5. ✓
- Dropdown tree UI + collapse + select → Task 9. ✓
- Drag & drop reparent/reorder + descendant guard → Tasks 5 (store guard) + 10 (UI). ✓
- "Close" → "Remove from GitOpen", non-destructive folder removal → Tasks 6 (remove), 4 (removeFolder reparents). ✓
- Retire `open_workspaces`, add `last_active_repo` → Task 8. ✓
- Migration v2→v3 (non-destructive column add) → Task 2 (+ migration test). ✓
- Error handling: cycle/orphan defense → Task 3; descendant-drop guard → Task 5; remove-active fallback → Tasks 8/9; persist-failure refresh → Task 7. ✓
- Testing strategy (pure tree, persistence, manager, widget) → Tasks 3,4,5,6,7,9,10. ✓
- Version bump for CD → Task 11. ✓

**Placeholder scan:** Task 10 Step 6 describes a widget test in prose then requires it be implemented concretely against the fake organizer — this is the one place exact final widget code is deferred to implementation because the drag-coordinate wiring depends on the rendered row geometry built in Step 5; the recording-fake pattern and the assertion target are specified, so it is actionable, not a TODO. All code steps elsewhere contain complete code. No "TBD"/"add error handling"/"similar to Task N".

**Type consistency:** `FolderId`, `RepoId`, `Folder`, `PlacedRepo`, `RepoTreeNode`/`FolderNode`/`RepoNode`, `RepoTreeStore` (`loadFolders`/`loadPlacedRepos`/`createFolder`/`renameFolder`/`setCollapsed`/`removeFolder`/`moveRepo`/`moveFolder`), `RepoOrganizer` (`refresh`/`createFolder`/.../`moveFolder`), `WorkspaceManager` (`loadAll`/`open`/`remove`/`find`), `WorkspacePersistence` (`getLastActiveRepoId`/`saveLastActiveRepoId`), `flattenVisible`/`VisibleRow`, `resolveDropIndex`, `DragRef`/`RepoDragRef`/`FolderDragRef` — names are consistent across the tasks that define and consume them. Drift-generated names (`FoldersCompanion`, `FolderData`, `RepositoriesCompanion`, `parentFolderId`) are noted as codegen-dependent in Task 4.
