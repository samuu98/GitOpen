import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/repo_id.dart';
import 'repository_registry.dart';
import 'workspace.dart';

final class WorkspaceManager extends StateNotifier<List<Workspace>> {
  final RepositoryRegistry _registry;
  WorkspaceManager(this._registry) : super(const []);

  Future<Workspace> open(String path) async {
    final loc = await _registry.add(path);
    final existing = state.firstWhereOrNull((w) => w.location.id == loc.id);
    if (existing != null) return existing;
    final ws = Workspace(loc);
    state = [...state, ws];
    await _registry.touchLastOpened(loc.id);
    return ws;
  }

  Future<void> close(RepoId id) async {
    state = state.where((w) => w.location.id != id).toList(growable: false);
  }

  Workspace? find(RepoId id) =>
      state.firstWhereOrNull((w) => w.location.id == id);

  void reorder(List<RepoId> newOrder) {
    final byId = {for (final w in state) w.location.id: w};
    state = [
      for (final id in newOrder)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }
}
