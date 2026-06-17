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
import 'package:gitopen/ui/shell/repo_tree_drag.dart';
import 'package:gitopen/ui/shell/repo_tree_popover.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

typedef _RepoMove = ({RepoId id, int atIndex, FolderId? toParent});

class _RecordingStore implements RepoTreeStore {
  _RecordingStore(this._repos);
  final List<PlacedRepo> _repos;
  final List<_RepoMove> repoMoves = [];

  @override
  Future<List<Folder>> loadFolders() async => const [];
  @override
  Future<List<PlacedRepo>> loadPlacedRepos() async => _repos;
  @override
  Future<void> moveRepo(
    RepoId id, {
    required int atIndex,
    FolderId? toParent,
  }) async {
    repoMoves.add((id: id, atIndex: atIndex, toParent: toParent));
  }

  @override
  Future<Folder> createFolder({required String name, FolderId? parentId}) =>
      throw UnimplementedError();
  @override
  Future<void> renameFolder(FolderId id, String name) async {}
  @override
  Future<void> setCollapsed(FolderId id, {required bool collapsed}) async {}
  @override
  Future<void> removeFolder(FolderId id) async {}
  @override
  Future<void> moveFolder(
    FolderId id, {
    required int atIndex,
    FolderId? toParent,
  }) async {}
}

void main() {
  group('resolveDropIndex', () {
    test('top half inserts before the hovered index', () {
      expect(resolveDropIndex(hoveredIndex: 3, isTopHalf: true), 3);
    });
    test('bottom half inserts after the hovered index', () {
      expect(resolveDropIndex(hoveredIndex: 3, isTopHalf: false), 4);
    });
  });

  group('adjustForSameParent', () {
    test('dragging downward shifts the target left by one', () {
      expect(adjustForSameParent(rawIndex: 3, movedIndex: 1), 2);
    });
    test('dragging upward leaves the target unchanged', () {
      expect(adjustForSameParent(rawIndex: 1, movedIndex: 3), 1);
    });
    test('equal index is unchanged', () {
      expect(adjustForSameParent(rawIndex: 2, movedIndex: 2), 2);
    });
  });

  group('zoneFor', () {
    test('repo rows split 50/50 into before/after', () {
      expect(zoneFor(fraction: 0.2, isFolder: false), DropZone.before);
      expect(zoneFor(fraction: 0.8, isFolder: false), DropZone.after);
    });
    test('folder rows have a central into-band', () {
      expect(zoneFor(fraction: 0.1, isFolder: true), DropZone.before);
      expect(zoneFor(fraction: 0.5, isFolder: true), DropZone.into);
      expect(zoneFor(fraction: 0.9, isFolder: true), DropZone.after);
    });
  });

  group('RepoTreePopover drag', () {
    testWidgets('dragging a repo onto another records a moveRepo',
        (tester) async {
      final store = _RecordingStore(const [
        PlacedRepo(
          location: RepoLocation(RepoId('a'), '/tmp/a', 'alpha'),
          parentId: null,
          sortOrder: 0,
        ),
        PlacedRepo(
          location: RepoLocation(RepoId('b'), '/tmp/b', 'beta'),
          parentId: null,
          sortOrder: 1,
        ),
      ]);
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
            home: const Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: RepoTreePopover(onDismiss: _noop),
              ),
            ),
          ),
        ),
      );

      expect(find.text('alpha'), findsOneWidget);
      expect(find.byType(DragTreeRow), findsNWidgets(2));

      // Drag 'alpha' down onto 'beta'.
      await tester.drag(find.text('alpha'), const Offset(0, 80));
      await tester.pumpAndSettle();

      expect(store.repoMoves, isNotEmpty);
      expect(store.repoMoves.first.id, const RepoId('a'));
      expect(store.repoMoves.first.toParent, isNull); // stays at root
    });
  });
}

void _noop() {}
