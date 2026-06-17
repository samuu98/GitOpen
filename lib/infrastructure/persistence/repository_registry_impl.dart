import 'package:drift/drift.dart';
import 'package:gitopen/application/workspaces/repository_registry.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/persistence/database.dart';
import 'package:path/path.dart' as p;

final class DriftRepositoryRegistry implements RepositoryRegistry {
  DriftRepositoryRegistry(this._db);
  final AppDatabase _db;

  @override
  Future<RepoLocation> add(String path) async {
    final existing = await (_db.select(_db.repositories)
          ..where((r) => r.path.equals(path)))
        .getSingleOrNull();
    if (existing != null) {
      return RepoLocation(
        RepoId(existing.id),
        existing.path,
        existing.displayName,
      );
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

  /// Next free order at the root (shared between root folders and root repos),
  /// so a newly added repo lands after existing root-level children.
  Future<int> _nextRootOrder() async {
    final folders = await (_db.select(_db.folders)
          ..where((f) => f.parentId.isNull()))
        .get();
    final repos = await (_db.select(_db.repositories)
          ..where((r) => r.parentFolderId.isNull()))
        .get();
    final orders = <int>[
      ...folders.map((f) => f.sortOrder),
      ...repos.map((r) => r.tabOrder),
    ];
    return orders.isEmpty ? 0 : (orders.reduce((a, b) => a > b ? a : b) + 1);
  }

  @override
  Future<List<RepoLocation>> list() async {
    final rows = await (_db.select(_db.repositories)
          ..orderBy([(r) => OrderingTerm(expression: r.tabOrder)]))
        .get();
    return rows
        .map((r) => RepoLocation(RepoId(r.id), r.path, r.displayName))
        .toList();
  }

  @override
  Future<RepoLocation?> getByPath(String path) async {
    final r = await (_db.select(_db.repositories)
          ..where((row) => row.path.equals(path)))
        .getSingleOrNull();
    if (r == null) return null;
    return RepoLocation(RepoId(r.id), r.path, r.displayName);
  }

  @override
  Future<void> remove(RepoId id) async {
    await (_db.delete(_db.repositories)
          ..where((r) => r.id.equals(id.value)))
        .go();
  }

  @override
  Future<void> touchLastOpened(RepoId id) async {
    await (_db.update(_db.repositories)
          ..where((r) => r.id.equals(id.value)))
        .write(
      RepositoriesCompanion(lastOpenedUtc: Value(DateTime.now().toUtc())),
    );
  }

  static String _displayName(String path) {
    final trimmed = path.replaceAll(RegExp(r'[/\\]+$'), '');
    final name = p.basename(trimmed);
    return name.isEmpty ? trimmed : name;
  }
}
