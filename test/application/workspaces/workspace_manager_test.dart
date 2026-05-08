import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/workspaces/repository_registry.dart';
import 'package:gitopen/application/workspaces/workspace_manager.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

class _FakeRegistry implements RepositoryRegistry {
  final Map<String, RepoLocation> _byPath = {};
  final List<RepoId> touched = [];

  @override
  Future<RepoLocation> add(String path) async {
    final existing = _byPath[path];
    if (existing != null) return existing;
    final loc = RepoLocation(RepoId.newId(), path, path.split('/').last);
    _byPath[path] = loc;
    return loc;
  }

  @override
  Future<List<RepoLocation>> list() async => _byPath.values.toList();

  @override
  Future<RepoLocation?> getByPath(String path) async => _byPath[path];

  @override
  Future<void> remove(RepoId id) async {
    _byPath.removeWhere((_, v) => v.id == id);
  }

  @override
  Future<void> touchLastOpened(RepoId id) async {
    touched.add(id);
  }
}

void main() {
  group('WorkspaceManager', () {
    test('open adds a workspace and emits new state', () async {
      final registry = _FakeRegistry();
      final sut = WorkspaceManager(registry);
      final ws = await sut.open('/x');
      expect(sut.state, hasLength(1));
      expect(sut.state.first.location.id, ws.location.id);
      expect(registry.touched, hasLength(1));
    });

    test('open returns existing when path already open', () async {
      final registry = _FakeRegistry();
      final sut = WorkspaceManager(registry);
      final a = await sut.open('/x');
      final b = await sut.open('/x');
      expect(b.location.id, a.location.id);
      expect(sut.state, hasLength(1));
    });

    test('close removes the workspace', () async {
      final registry = _FakeRegistry();
      final sut = WorkspaceManager(registry);
      final ws = await sut.open('/x');
      await sut.close(ws.location.id);
      expect(sut.state, isEmpty);
    });
  });
}
