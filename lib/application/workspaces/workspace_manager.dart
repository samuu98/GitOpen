import 'package:collection/collection.dart';
import 'package:flutter_riverpod/legacy.dart';
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

  /// Forgets a repo from the catalog (does not touch the disk).
  Future<void> remove(RepoId id) async {
    await _registry.remove(id);
    state = state.where((w) => w.location.id != id).toList(growable: false);
  }

  Workspace? find(RepoId id) =>
      state.firstWhereOrNull((w) => w.location.id == id);
}
