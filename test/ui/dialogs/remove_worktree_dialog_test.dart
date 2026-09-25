import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/remove_worktree_dialog.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/operations.dart';

const _repo = RepoLocation(RepoId('test'), 'C:/main', 'test');
const _worktree = Worktree(path: 'C:/feature', branch: 'feature');

/// Clean worktree, branch reported as [merged]. Merged, the refusal can then
/// only come from git itself, which is the case this dialog has to survive.
class _Inspector implements BranchDeletionInspector {
  _Inspector({required this.merged});

  final bool merged;

  @override
  Future<BranchDeleteStatus> inspect(RepoLocation repo, String branch) async =>
      BranchDeleteStatus(exists: true, merged: merged);

  @override
  Future<WorktreeDeleteStatus?> inspectWorktree(
    RepoLocation repo,
    String path,
  ) async => WorktreeDeleteStatus(
    path: path,
    branch: 'feature',
    isMain: false,
    dirty: false,
    locked: false,
  );
}

class _Write implements GitWriteOperations {
  int removals = 0;
  final List<bool> deletes = [];

  @override
  Future<GitResult<void>> removeWorktree(
    RepoLocation repo,
    String path, {
    bool force = false,
  }) async {
    removals++;
    return const GitSuccess(null);
  }

  @override
  Future<GitResult<void>> deleteBranch(
    RepoLocation repo,
    String name, {
    bool force = false,
    bool remote = false,
  }) async {
    deletes.add(force);
    return force
        ? const GitSuccess(null)
        : const GitFailure(
            GitErrorKind.other,
            "error: the branch 'feature' is not fully merged",
          );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _open(
  WidgetTester tester,
  _Write write, {
  bool failRefresh = false,
  bool merged = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        branchDeletionFlowProvider.overrideWithValue(
          BranchDeletionFlow(
            inspector: _Inspector(merged: merged),
            write: write,
          ),
        ),
        operationsProvider.overrideWith(
          (ref) => OperationsNotifier(InMemoryActivityLog()),
        ),
        if (failRefresh)
          sidebarDataProvider(_repo).overrideWith(
            (ref) async => throw StateError('sidebar reload failed'),
          ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                if (failRefresh)
                  Consumer(
                    builder: (context, ref, _) => Text(
                      'sidebar:'
                      '${ref.watch(sidebarDataProvider(_repo)).hasError}',
                    ),
                  ),
                ElevatedButton(
                  onPressed: () => RemoveWorktreeDialog.show(
                    context,
                    repo: _repo,
                    worktree: _worktree,
                  ),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a branch git refuses is offered force after the removal', (
    tester,
  ) async {
    final write = _Write();
    await _open(tester, write);
    await tester.tap(find.text('Also delete the branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove worktree'));
    await tester.pumpAndSettle();

    expect(write.removals, 1);
    expect(write.deletes, [false]);
    expect(find.text('Remove worktree?'), findsOneWidget);
    expect(find.textContaining('The worktree was removed'), findsOneWidget);
    expect(find.textContaining('error: the branch'), findsNothing);
    expect(find.text('Force delete unmerged branch'), findsOneWidget);
    expect(
      find.text('Delete branch'),
      findsOneWidget,
      reason: 'the worktree is gone; only the branch is left to do',
    );

    await tester.tap(find.text('Force delete unmerged branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Force delete'));
    await tester.pumpAndSettle();

    expect(write.removals, 1, reason: 'the worktree is not removed twice');
    expect(write.deletes, [false, true]);
    expect(find.text('Remove worktree?'), findsNothing);
  });

  testWidgets('a refresh failure closes the dialog with no message', (
    tester,
  ) async {
    final write = _Write();
    await _open(tester, write, failRefresh: true);
    await tester.tap(find.text('Remove worktree'));
    await tester.pumpAndSettle();

    expect(write.removals, 1);
    expect(find.text('Remove worktree?'), findsNothing);
    expect(
      find.text(refreshFailureMessage),
      findsNothing,
      reason: "the runner's toast is the only refresh-failure message",
    );
    final operations = ProviderScope.containerOf(
      tester.element(find.text('open')),
    ).read(operationsProvider);
    expect(
      operations.where((o) => o.errorMessage == refreshFailureMessage),
      hasLength(1),
    );
  });

  testWidgets('an unmerged branch keeps the worktree until force is chosen', (
    tester,
  ) async {
    final write = _Write();
    await _open(tester, write, merged: false);
    await tester.tap(find.text('Also delete the branch'));
    await tester.pumpAndSettle();
    expect(find.text('Force delete unmerged branch'), findsOneWidget);
    await tester.tap(find.text('Remove worktree'));
    await tester.pumpAndSettle();

    expect(write.removals, 0, reason: 'nothing is removed without force');
    expect(write.deletes, isEmpty);
    expect(find.textContaining('Enable force delete'), findsOneWidget);
    expect(
      find.text('Remove worktree'),
      findsOneWidget,
      reason: 'the worktree is still there to remove',
    );

    await tester.tap(find.text('Force delete unmerged branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove worktree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Force delete'));
    await tester.pumpAndSettle();

    expect(write.removals, 1);
    expect(write.deletes, [true]);
    expect(find.text('Remove worktree?'), findsNothing);
  });
}
