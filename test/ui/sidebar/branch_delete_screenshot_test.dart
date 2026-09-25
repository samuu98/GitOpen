import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/delete_branch_dialog.dart';
import 'package:gitopen/ui/dialogs/remove_worktree_dialog.dart';
import 'package:gitopen/ui/sidebar/branch_tree.dart';
import 'package:gitopen/ui/sidebar/branch_tree_view.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/operations.dart';
import '../../_helpers/screenshot.dart';

const _repo = RepoLocation(RepoId('screenshots'), 'unused', 'GitOpen');
const _one = Branch(
  name: 'task/one',
  fullName: 'refs/heads/task/one',
  isRemote: false,
  isCurrent: false,
  ahead: 0,
  behind: 0,
);
const _two = Branch(
  name: 'task/two',
  fullName: 'refs/heads/task/two',
  isRemote: false,
  isCurrent: false,
  ahead: 0,
  behind: 0,
);
const _linked = Branch(
  name: 'linked',
  fullName: 'refs/heads/linked',
  isRemote: false,
  isCurrent: false,
  ahead: 0,
  behind: 0,
);

class _Inspector implements BranchDeletionInspector {
  @override
  Future<BranchDeleteStatus> inspect(RepoLocation repo, String name) async =>
      BranchDeleteStatus(
        exists: true,
        merged: true,
        worktreePath: name == 'linked' ? 'C:/projects/linked' : null,
      );

  @override
  Future<WorktreeDeleteStatus?> inspectWorktree(
    RepoLocation repo,
    String path,
  ) async => WorktreeDeleteStatus(
    path: path,
    branch: 'linked',
    isMain: false,
    dirty: true,
    locked: false,
  );
}

class _Write implements GitWriteOperations {
  _Write({this.refuse = false});

  /// Answers an unforced delete the way git answers a branch that is not
  /// merged into its upstream.
  final bool refuse;
  final first = Completer<GitResult<void>>();
  final second = Completer<GitResult<void>>();
  int calls = 0;

  @override
  Future<GitResult<void>> removeWorktree(
    RepoLocation repo,
    String path, {
    bool force = false,
  }) async => const GitSuccess(null);

  @override
  Future<GitResult<void>> deleteBranch(
    RepoLocation repo,
    String name, {
    bool force = false,
    bool remote = false,
  }) {
    calls++;
    if (refuse && !force) {
      return Future.value(
        const GitFailure(
          GitErrorKind.other,
          "error: the branch 'linked' is not fully merged",
        ),
      );
    }
    return calls == 1 ? first.future : second.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _SettingsStore implements SettingsStore {
  @override
  Future<Map<String, dynamic>> readAll() async => const {};
  @override
  Future<void> put(String key, dynamic value) async {}
}

void main() {
  setUpAll(loadAppFonts);
  final shots = PipelineScreenshotComparator('branch-delete');

  Future<void> capture(WidgetTester tester, String name) async {
    await expectLater(find.byKey(const Key('shot')), matchesGoldenFile(name));
    expect(shots.fileFor(name).existsSync(), isTrue);
  }

  Future<void> host(WidgetTester tester, Widget home, _Write write) async {
    await tester.binding.setSurfaceSize(const Size(950, 650));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot'),
        child: ProviderScope(
          overrides: [
            branchDeletionFlowProvider.overrideWithValue(
              BranchDeletionFlow(
                inspector: _Inspector(),
                write: write,
              ),
            ),
            appSettingsProvider.overrideWith(
              (ref) => AppSettingsNotifier(_SettingsStore()),
            ),
            operationsProvider.overrideWith(
              (ref) => OperationsNotifier(InMemoryActivityLog()),
            ),
            branchDivergenceProvider(_repo).overrideWith(
              (ref) async => const <String, ({int ahead, int behind})>{},
            ),
          ],
          child: screenshotApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: AppPalette.dark().bg0,
              extensions: [
                AppPalette.dark(),
                const AppSpacing.desktop(),
                const AppRadii.desktop(),
                const AppTypography.desktop(),
                const AppMotion.standard(),
              ],
            ),
            home: Scaffold(body: home),
          ),
        ),
      ),
    );
  }

  testWidgets('tree multi-selection screenshot', (tester) async {
    final previous = goldenFileComparator;
    goldenFileComparator = shots;
    addTearDown(() => goldenFileComparator = previous);
    await host(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 320,
          child: BranchTreeView(
            nodes: BranchTree.build(const [_one, _two, _linked]),
            repo: _repo,
          ),
        ),
      ),
      _Write(),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('one'));
    await tester.tap(find.text('two'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await capture(tester, 'tree_multi_selection.png');
  });

  testWidgets('batch progress and result screenshots', (tester) async {
    final previous = goldenFileComparator;
    goldenFileComparator = shots;
    addTearDown(() => goldenFileComparator = previous);
    final write = _Write();
    await host(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => DeleteBranchesDialog.show(
              context,
              repo: _repo,
              branches: const [_one, _two],
              allBranches: const [_one, _two],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      write,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete 2 branches'));
    await tester.pump();
    write.first.complete(const GitSuccess(null));
    for (var i = 0; i < 30 && write.calls < 2; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Deleting 1 of 2…'), findsOneWidget);
    await pumpUntilPending(tester, find.byType(CircularProgressIndicator));
    await capture(tester, 'multi_delete_progress.png');
    write.second.complete(
      const GitFailure(GitErrorKind.other, 'remote rejected deletion'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('remote rejected deletion'), findsOneWidget);
    await capture(tester, 'multi_delete_results.png');
  });

  testWidgets('single linked branch screenshot', (tester) async {
    final previous = goldenFileComparator;
    goldenFileComparator = shots;
    addTearDown(() => goldenFileComparator = previous);
    await host(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => DeleteBranchesDialog.show(
              context,
              repo: _repo,
              branches: const [_linked],
              allBranches: const [_linked],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      _Write(),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Also remove the worktree'), findsOneWidget);
    await capture(tester, 'single_linked_worktree.png');
  });

  testWidgets('worktree removal screenshot', (tester) async {
    final previous = goldenFileComparator;
    goldenFileComparator = shots;
    addTearDown(() => goldenFileComparator = previous);
    await host(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => RemoveWorktreeDialog.show(
              context,
              repo: _repo,
              worktree: const Worktree(
                path: 'C:/projects/linked',
                branch: 'linked',
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      _Write(),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Also delete the branch'), findsOneWidget);
    await capture(tester, 'remove_worktree.png');
  });

  testWidgets('branch refused after its worktree went screenshot', (
    tester,
  ) async {
    final previous = goldenFileComparator;
    goldenFileComparator = shots;
    addTearDown(() => goldenFileComparator = previous);
    await host(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => DeleteBranchesDialog.show(
              context,
              repo: _repo,
              branches: const [_linked],
              allBranches: const [_linked],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      _Write(refuse: true),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Also remove the worktree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enable force delete'), findsWidgets);
    expect(find.text('Force delete unmerged branches'), findsOneWidget);
    await capture(tester, 'branch_delete_force_offer.png');
  });

  testWidgets('worktree removal leaving a refused branch screenshot', (
    tester,
  ) async {
    final previous = goldenFileComparator;
    goldenFileComparator = shots;
    addTearDown(() => goldenFileComparator = previous);
    await host(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => RemoveWorktreeDialog.show(
              context,
              repo: _repo,
              worktree: const Worktree(
                path: 'C:/projects/linked',
                branch: 'linked',
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      _Write(refuse: true),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Also delete the branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove worktree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Force remove'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enable force delete'), findsOneWidget);
    expect(find.text('Delete branch'), findsOneWidget);
    await capture(tester, 'remove_worktree_force_offer.png');
  });
}
