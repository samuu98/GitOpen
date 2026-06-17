import 'package:flutter_test/flutter_test.dart';
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
  Future<Folder> createFolder({
    required String name,
    FolderId? parentId,
  }) async {
    final f = Folder(
      id: FolderId.newId(),
      name: name,
      parentId: parentId,
      sortOrder: _order++,
      collapsed: false,
    );
    folders.add(f);
    return f;
  }

  @override
  Future<void> renameFolder(FolderId id, String name) async {}
  @override
  Future<void> setCollapsed(FolderId id, {required bool collapsed}) async {}
  @override
  Future<void> removeFolder(FolderId id) async {
    folders.removeWhere((f) => f.id == id);
  }

  @override
  Future<void> moveRepo(
    RepoId id, {
    required int atIndex,
    FolderId? toParent,
  }) async {}
  @override
  Future<void> moveFolder(
    FolderId id, {
    required int atIndex,
    FolderId? toParent,
  }) async {}
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

  test('removeFolder reloads truth even though state changes', () async {
    final store = _FakeStore();
    final sut = RepoOrganizer(store);
    final id = await sut.createFolder('Temp');
    expect(sut.state, hasLength(1));
    await sut.removeFolder(id);
    expect(sut.state, isEmpty);
  });
}
