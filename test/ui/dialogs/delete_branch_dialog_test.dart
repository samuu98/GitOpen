import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/delete_branch_dialog.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/operations.dart';

class _Inspector implements BranchDeletionInspector {
  @override
  Future<BranchDeleteStatus> inspect(RepoLocation repo, String branch) async =>
      BranchDeleteStatus(
        exists: true,
        merged: branch == 'one',
        worktreePath: branch == 'two' ? '/tmp/two' : null,
      );

  @override
  Future<WorktreeDeleteStatus?> inspectWorktree(
    RepoLocation repo,
    String path,
  ) async => null;
}

class _Write implements GitWriteOperations {
  _Write({this.refuse = true});

  /// Whether the unforced delete is refused, as git does for a branch that is
  /// not merged into its upstream.
  final bool refuse;
  final List<bool> deletes = [];

  @override
  Future<GitResult<void>> deleteBranch(
    RepoLocation repo,
    String name, {
    bool force = false,
    bool remote = false,
  }) async {
    deletes.add(force);
    // Git's own refusal, which only `-D` gets past.
    return force || !refuse
        ? const GitSuccess(null)
        : const GitFailure(
            GitErrorKind.other,
            "error: the branch 'feature' is not fully merged",
          );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Reports every branch as [merged]. Merged, the dialog only learns about the
/// refusal from git itself — the race the pre-check cannot close.
class _MergedInspector implements BranchDeletionInspector {
  _MergedInspector({required this.merged});

  final bool merged;

  @override
  Future<BranchDeleteStatus> inspect(RepoLocation repo, String branch) async =>
      BranchDeleteStatus(exists: true, merged: merged);

  @override
  Future<WorktreeDeleteStatus?> inspectWorktree(
    RepoLocation repo,
    String path,
  ) async => null;
}

const _feature = Branch(
  name: 'feature',
  fullName: 'refs/heads/feature',
  isRemote: false,
  isCurrent: false,
  ahead: 0,
  behind: 0,
);

/// Opens [DeleteBranchesDialog] over a host that can also watch the sidebar
/// provider, so a failing reload reaches the runner as a refresh failure.
Future<void> _openBatch(
  WidgetTester tester,
  _Write write, {
  bool failRefresh = false,
  bool merged = true,
}) async {
  const repo = RepoLocation(RepoId('test'), 'unused', 'test');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        branchDeletionFlowProvider.overrideWithValue(
          BranchDeletionFlow(
            inspector: _MergedInspector(merged: merged),
            write: write,
          ),
        ),
        operationsProvider.overrideWith(
          (ref) => OperationsNotifier(InMemoryActivityLog()),
        ),
        if (failRefresh)
          sidebarDataProvider(repo).overrideWith(
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
                      '${ref.watch(sidebarDataProvider(repo)).hasError}',
                    ),
                  ),
                ElevatedButton(
                  onPressed: () => DeleteBranchesDialog.show(
                    context,
                    repo: repo,
                    branches: const [_feature],
                    allBranches: const [_feature],
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

/// Opens the dialog and returns its future inside a record, so the caller's
/// `await` does NOT flatten/await the dialog future itself (which only
/// completes once the user taps an action).
Future<({Future<DeleteBranchSelection?> dialog})> _open(
  WidgetTester tester,
  BranchDeletionTargets targets,
) async {
  late Future<DeleteBranchSelection?> dialog;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  dialog = DeleteBranchDialog.show(context, targets: targets),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return (dialog: dialog);
}

void main() {
  testWidgets('batch dialog lists worktree path and deletion status', (
    tester,
  ) async {
    const repo = RepoLocation(RepoId('test'), 'unused', 'test');
    const branches = [
      Branch(
        name: 'one',
        fullName: 'refs/heads/one',
        isRemote: false,
        isCurrent: false,
        ahead: 0,
        behind: 0,
      ),
      Branch(
        name: 'two',
        fullName: 'refs/heads/two',
        isRemote: false,
        isCurrent: false,
        ahead: 0,
        behind: 0,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          branchDeletionFlowProvider.overrideWithValue(
            BranchDeletionFlow(inspector: _Inspector(), write: _Write()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => DeleteBranchesDialog.show(
                  context,
                  repo: repo,
                  branches: branches,
                  allBranches: branches,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 branches?'), findsOneWidget);
    expect(find.text('one'), findsWidgets);
    expect(find.text('two'), findsWidgets);
    expect(find.textContaining('/tmp/two'), findsOneWidget);
    expect(find.textContaining('Unmerged'), findsOneWidget);
  });
  testWidgets('shows both sides and returns both selected by default', (
    tester,
  ) async {
    final h = await _open(
      tester,
      const BranchDeletionTargets(
        localName: 'feature',
        remoteRef: 'origin/feature',
      ),
    );
    expect(find.text('Local branch feature'), findsOneWidget);
    expect(find.text('Remote branch origin/feature'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final sel = await h.dialog;
    expect(sel!.deleteLocal, isTrue);
    expect(sel.deleteRemote, isTrue);
  });

  testWidgets('current local branch cannot be selected', (tester) async {
    final h = await _open(
      tester,
      const BranchDeletionTargets(
        localName: 'main',
        localIsCurrent: true,
        remoteRef: 'origin/main',
      ),
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final sel = await h.dialog;
    expect(sel!.deleteLocal, isFalse); // disabled -> not selected
    expect(sel.deleteRemote, isTrue);
  });

  testWidgets('only the remote side when there is no local', (tester) async {
    final h = await _open(
      tester,
      const BranchDeletionTargets(remoteRef: 'origin/feature'),
    );
    expect(find.textContaining('Local branch'), findsNothing);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final sel = await h.dialog;
    expect(sel!.deleteLocal, isFalse);
    expect(sel.deleteRemote, isTrue);
  });

  testWidgets('a branch git refuses is offered force, not a dead end', (
    tester,
  ) async {
    final write = _Write();
    await _openBatch(tester, write);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(write.deletes, [false]);
    expect(find.textContaining('Unmerged'), findsOneWidget);
    expect(
      find.textContaining('error: the branch'),
      findsNothing,
      reason: "git's stderr is replaced by the app's own words",
    );
    expect(find.textContaining('Enable force delete'), findsOneWidget);

    await tester.tap(find.text('Force delete unmerged branches'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Force delete').last);
    await tester.pumpAndSettle();
    expect(write.deletes, [false, true]);
    expect(find.text('Deleted 1 of 1 branches'), findsOneWidget);
  });

  testWidgets('a refresh failure leaves the dialog on its result', (
    tester,
  ) async {
    final write = _Write(refuse: false);
    await _openBatch(tester, write, failRefresh: true);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(write.deletes, [false]);
    expect(find.text('Deleted 1 of 1 branches'), findsOneWidget);
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

  testWidgets('an unmerged branch needs force before anything runs', (
    tester,
  ) async {
    final write = _Write();
    await _openBatch(tester, write, merged: false);
    expect(find.textContaining('Unmerged'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(write.deletes, isEmpty, reason: 'Delete waits for force');

    await tester.tap(find.text('Force delete unmerged branches'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Force delete').last);
    await tester.pumpAndSettle();
    expect(write.deletes, [true]);
    expect(find.text('Deleted 1 of 1 branches'), findsOneWidget);
  });
}
