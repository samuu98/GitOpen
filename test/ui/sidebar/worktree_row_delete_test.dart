import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/sidebar/worktree_row.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class _Inspector implements BranchDeletionInspector {
  _Inspector({this.dirty = true});
  final bool dirty;

  @override
  Future<BranchDeleteStatus> inspect(RepoLocation repo, String branch) async =>
      const BranchDeleteStatus(exists: true, merged: true);

  @override
  Future<WorktreeDeleteStatus?> inspectWorktree(
    RepoLocation repo,
    String path,
  ) async => WorktreeDeleteStatus(
    path: path,
    branch: 'feature',
    isMain: false,
    dirty: dirty,
    locked: false,
  );
}

class _Write implements GitWriteOperations {
  final pending = Completer<GitResult<void>>();

  @override
  Future<GitResult<void>> removeWorktree(
    RepoLocation repo,
    String path, {
    bool force = false,
  }) => pending.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('remove menu opens worktree dialog with dirty warning', (
    tester,
  ) async {
    const repo = RepoLocation(RepoId('test'), 'C:/main', 'test');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          branchDeletionFlowProvider.overrideWithValue(
            BranchDeletionFlow(inspector: _Inspector(), write: _Write()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: const Scaffold(
            body: WorktreeRow(
              worktree: Worktree(path: 'C:/feature', branch: 'feature'),
              repo: repo,
              onRefresh: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('feature').first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove worktree'));
    await tester.pumpAndSettle();
    expect(find.text('Remove worktree?'), findsOneWidget);
    expect(find.textContaining('C:/feature'), findsWidgets);
    expect(find.textContaining('Uncommitted or untracked'), findsOneWidget);
    expect(find.text('Also delete the branch'), findsOneWidget);
  });

  testWidgets('remove dialog opens after sidebar row is replaced', (
    tester,
  ) async {
    const repo = RepoLocation(RepoId('test'), 'C:/main', 'test');
    final showRow = ValueNotifier(true);
    addTearDown(showRow.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          branchDeletionFlowProvider.overrideWithValue(
            BranchDeletionFlow(inspector: _Inspector(), write: _Write()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showRow,
              builder: (context, visible, child) => visible
                  ? const WorktreeRow(
                      worktree: Worktree(
                        path: 'C:/feature',
                        branch: 'feature',
                      ),
                      repo: repo,
                      onRefresh: _noop,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('feature').first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    showRow.value = false;
    await tester.pump();
    await tester.tap(find.text('Remove worktree'));
    await tester.pumpAndSettle();
    expect(find.text('Remove worktree?'), findsOneWidget);
  });

  testWidgets('removal stays busy until the action completes', (
    tester,
  ) async {
    const repo = RepoLocation(RepoId('test'), 'C:/main', 'test');
    final write = _Write();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          branchDeletionFlowProvider.overrideWithValue(
            BranchDeletionFlow(
              inspector: _Inspector(dirty: false),
              write: write,
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: const Scaffold(
            body: WorktreeRow(
              worktree: Worktree(path: 'C:/feature', branch: 'feature'),
              repo: repo,
              onRefresh: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('feature').first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove worktree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove worktree').last);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final removeButton = tester.widget<AppButton>(
      find.byWidgetPredicate(
        (widget) => widget is AppButton && widget.label == 'Remove worktree',
      ),
    );
    expect(removeButton.onPressed, isNull);
    write.pending.complete(
      const GitFailure(GitErrorKind.other, 'removal failed'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('removal failed'), findsOneWidget);
  });
}

void _noop() {}
