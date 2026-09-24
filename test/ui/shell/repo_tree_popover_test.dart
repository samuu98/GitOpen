import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/launcher/folder_picker.dart';
import 'package:gitopen/application/operations/activity_log_store.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/application/workspaces/repo_tree_store.dart';
import 'package:gitopen/application/workspaces/repository_registry.dart';
import 'package:gitopen/application/workspaces/workspace_manager.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/shell/repo_tree_popover.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import '../../_helpers/repository_validator.dart';

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
  }) => throw UnimplementedError();
  @override
  Future<void> moveFolder(
    FolderId id, {
    required int atIndex,
    FolderId? toParent,
  }) => throw UnimplementedError();
}

/// Folder picker whose result the test completes manually, so the popover can
/// be dismissed *during* the pick (the exact timing that triggered the bug).
class _FakePicker implements FolderPicker {
  final Completer<String?> completer = Completer<String?>();
  @override
  Future<String?> pickFolder(String title) => completer.future;
}

/// Registry that records the paths it was asked to add.
class _RecordingRegistry implements RepositoryRegistry {
  final List<String> added = [];
  final List<RepoId> touched = [];
  @override
  Future<RepoLocation> add(String path) async {
    added.add(path);
    final name = path.split(RegExp(r'[\\/]')).last;
    return RepoLocation(RepoId('id-$path'), path, name);
  }

  @override
  Future<List<RepoLocation>> list() async => const [];
  @override
  Future<RepoLocation?> getByPath(String path) async => null;
  @override
  Future<void> remove(RepoId id) async {}
  @override
  Future<void> touchLastOpened(RepoId id) async => touched.add(id);
}

class _FakeLogStore implements ActivityLogStore {
  @override
  Future<void> clearCompleted() async {}

  @override
  Future<List<RunningOperation>> recent({int limit = 50}) async => const [];

  @override
  Future<void> upsert(RunningOperation op) async {}
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

    testWidgets('tapping a folder collapses it and hides the repo', (
      tester,
    ) async {
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

    testWidgets('selecting a repository records it as recently opened', (
      tester,
    ) async {
      final registry = _RecordingRegistry();
      final store = _FakeTreeStore(
        [],
        const [
          PlacedRepo(
            location: RepoLocation(RepoId('a'), '/tmp/a', 'alpha'),
            parentId: null,
            sortOrder: 0,
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          repoTreeStoreProvider.overrideWithValue(store),
          workspaceManagerProvider.overrideWith(
            (ref) => WorkspaceManager(
              registry,
              const PassThroughRepositoryValidator(),
            ),
          ),
          operationsProvider.overrideWith(
            (ref) => OperationsNotifier(_FakeLogStore()),
          ),
        ],
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

      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();

      expect(registry.added, ['/tmp/a']);
      expect(registry.touched, [const RepoId('id-/tmp/a')]);
      expect(
        container.read(activeWorkspaceIdProvider),
        const RepoId('id-/tmp/a'),
      );
    });
  });

  group('open flows survive the popover being dismissed', () {
    testWidgets('Open repository still adds the repo after onDismiss', (
      tester,
    ) async {
      // Repro: onDismiss() hides the OverlayPortal (disposing the popover)
      // BEFORE the folder picker resolves. The continuation must not depend
      // on the disposed widget's `ref`, or the repo is silently never added.
      final picker = _FakePicker();
      final registry = _RecordingRegistry();
      final store = _FakeTreeStore([], []);
      final container = ProviderContainer(
        overrides: [
          repoTreeStoreProvider.overrideWithValue(store),
          folderPickerProvider.overrideWithValue(picker),
          workspaceManagerProvider.overrideWith(
            (ref) => WorkspaceManager(
              registry,
              const PassThroughRepositoryValidator(),
            ),
          ),
          operationsProvider.overrideWith(
            (ref) => OperationsNotifier(_FakeLogStore()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(repoOrganizerProvider.notifier).refresh();

      var show = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppPalette.dark()]),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => show
                    ? RepoTreePopover(
                        onDismiss: () => setState(() => show = false),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open repository…'));
      // _openRepo ran up to the await; onDismiss fired -> rebuild disposes it.
      await tester.pump();
      expect(find.byType(RepoTreePopover), findsNothing); // popover is gone
      // Now the picker resolves — the continuation must still add the repo.
      picker.completer.complete(r'C:\repos\demo');
      await tester.pumpAndSettle();

      expect(registry.added, contains(r'C:\repos\demo'));
    });
  });
}
