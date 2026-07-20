import 'package:collection/collection.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gitopen/application/workspaces/repository_registry.dart';
import 'package:gitopen/application/workspaces/repository_validator.dart';
import 'package:gitopen/application/workspaces/workspace.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';

final class WorkspaceManager extends StateNotifier<List<Workspace>> {
  WorkspaceManager(this._registry, this._validator) : super(const []);
  final RepositoryRegistry _registry;
  final RepositoryValidator _validator;

  /// Loads the full catalog from the registry. Called once at startup.
  Future<void> loadAll() async {
    final locations = await _registry.list();
    state = [for (final loc in locations) Workspace(loc)];
  }

  Future<Workspace> open(String path) async {
    final canonicalPath = await _validator.validate(path);
    final loc = await _registry.add(canonicalPath);
    final existing = state.firstWhereOrNull((w) => w.location.id == loc.id);
    if (existing != null) {
      await _registry.touchLastOpened(loc.id);
      // WorkspaceManager order backs the welcome screen's Recent list. Keep
      // the repository tree's explicit drag order in RepoTreeStore instead.
      state = [existing, ...state.where((w) => w.location.id != loc.id)];
      return existing;
    }
    final ws = Workspace(loc);
    await _registry.touchLastOpened(loc.id);
    state = [ws, ...state];
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
