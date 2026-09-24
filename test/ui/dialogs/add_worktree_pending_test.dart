import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/add_worktree_dialog.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets(
    'add worktree stays busy until sidebar reload and ignores repeat',
    (
      tester,
    ) async {
      const repo = RepoLocation(RepoId('repo'), 'C:/repo', 'repo');
      final write = _Write();
      final reload = Completer<SidebarData>();
      var loads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gitWriteOperationsProvider.overrideWithValue(write),
            sidebarDataProvider.overrideWith((ref, repo) {
              loads++;
              return loads == 1
                  ? Future.value(SidebarData([], [], [], [], [], []))
                  : reload.future;
            }),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: [AppPalette.dark()]),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  ref.watch(sidebarDataProvider(repo));
                  return TextButton(
                    onPressed: () => AddWorktreeDialog.show(context, repo),
                    child: const Text('Add'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'C:/repo-worktree');
      await tester.tap(find.text('Create'));
      await tester.pump();
      expect(write.calls, 1);
      write.done.complete(const GitSuccess(null));
      await tester.pump(const Duration(milliseconds: 350));
      expect(loads, 2);
      expect(find.text('Add worktree'), findsOneWidget);
      await tester.tap(find.text('Create'), warnIfMissed: false);
      await tester.pump();
      expect(write.calls, 1);
      reload.complete(SidebarData([], [], [], [], [], []));
      await tester.pumpAndSettle();
      expect(find.text('Add worktree'), findsNothing);
    },
  );
}

final class _Write implements GitWriteOperations {
  final done = Completer<GitResult<void>>();
  int calls = 0;
  @override
  Future<GitResult<void>> addWorktree(
    RepoLocation repo,
    String path, {
    String? newBranch,
    String? ref,
  }) {
    calls++;
    return done.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}
