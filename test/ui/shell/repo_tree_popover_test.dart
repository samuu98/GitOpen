import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/application/workspaces/repo_tree_store.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/shell/repo_tree_popover.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

RepoNode _repo(String id) =>
    RepoNode(RepoLocation(RepoId(id), '/p/$id', id), 0);

/// In-memory store for widget tests; only the methods the popover exercises
/// during these tests do real work.
class _FakeTreeStore implements RepoTreeStore {
  _FakeTreeStore(this.folders, this.repos);
  final List<Folder> folders;
  final List<PlacedRepo> repos;

  @override
  Future<List<Folder>> loadFolders() async => List.of(folders);
  @override
  Future<List<PlacedRepo>> loadPlacedRepos() async => List.of(repos);

  @override
  Future<void> setCollapsed(FolderId id, {required bool collapsed}) async {
    final i = folders.indexWhere((f) => f.id == id);
    if (i >= 0) folders[i] = folders[i].copyWith(collapsed: collapsed);
  }

  @override
  Future<Folder> createFolder({required String name, FolderId? parentId}) =>
      throw UnimplementedError();
  @override
  Future<void> renameFolder(FolderId id, String name) async {}
  @override
  Future<void> removeFolder(FolderId id) async {}
  @override
  Future<void> moveRepo(
    RepoId id, {
    required int atIndex,
    FolderId? toParent,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> moveFolder(
    FolderId id, {
    required int atIndex,
    FolderId? toParent,
  }) =>
      throw UnimplementedError();
}

Future<ProviderContainer> _pumpPopover(
  WidgetTester tester,
  _FakeTreeStore store,
) async {
  final container = ProviderContainer(
    overrides: [repoTreeStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  await container.read(repoOrganizerProvider.notifier).refresh();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(body: RepoTreePopover(onDismiss: () {})),
      ),
    ),
  );
  return container;
}

void main() {
  group('flattenVisible', () {
    test('hides descendants of a collapsed folder', () {
      final collapsed = FolderNode(
        const Folder(
          id: FolderId('f'),
          name: 'Work',
          parentId: null,
          sortOrder: 0,
          collapsed: true,
        ),
        [_repo('r')],
      );
      final rows = flattenVisible([collapsed]);
      expect(rows, hasLength(1)); // folder only, child hidden
      expect((rows.single.node as FolderNode).folder.name, 'Work');
    });

    test('shows descendants of an expanded folder with depth', () {
      final expanded = FolderNode(
        const Folder(
          id: FolderId('f'),
          name: 'Work',
          parentId: null,
          sortOrder: 0,
          collapsed: false,
        ),
        [_repo('r')],
      );
      final rows = flattenVisible([expanded]);
      expect(rows, hasLength(2));
      expect(rows[0].depth, 0);
      expect(rows[1].depth, 1);
    });

    test('records parent and sibling index for each row', () {
      final tree = [
        _repo('a'),
        FolderNode(
          const Folder(
            id: FolderId('f'),
            name: 'Work',
            parentId: null,
            sortOrder: 1,
            collapsed: false,
          ),
          [_repo('b'), _repo('c')],
        ),
      ];
      final rows = flattenVisible(tree);
      expect(rows.map((r) => r.indexInParent), [0, 1, 0, 1]);
      expect(rows[0].parentId, isNull); // root repo a
      expect(rows[2].parentId, const FolderId('f')); // b inside Work
      expect(rows[3].indexInParent, 1); // c is second child
    });
  });

  group('RepoTreePopover', () {
    testWidgets('renders a folder and its repo', (tester) async {
      final store = _FakeTreeStore(
        [
          const Folder(
            id: FolderId('f'),
            name: 'Work',
            parentId: null,
            sortOrder: 0,
            collapsed: false,
          ),
        ],
        const [
          PlacedRepo(
            location: RepoLocation(RepoId('a'), '/tmp/a', 'alpha'),
            parentId: FolderId('f'),
            sortOrder: 0,
          ),
        ],
      );
      await _pumpPopover(tester, store);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
    });

    testWidgets('tapping a folder collapses it and hides the repo',
        (tester) async {
      final store = _FakeTreeStore(
        [
          const Folder(
            id: FolderId('f'),
            name: 'Work',
            parentId: null,
            sortOrder: 0,
            collapsed: false,
          ),
        ],
        const [
          PlacedRepo(
            location: RepoLocation(RepoId('a'), '/tmp/a', 'alpha'),
            parentId: FolderId('f'),
            sortOrder: 0,
          ),
        ],
      );
      await _pumpPopover(tester, store);
      expect(find.text('alpha'), findsOneWidget);
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsNothing); // child hidden when collapsed
    });
  });
}
