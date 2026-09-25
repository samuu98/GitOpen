import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/add_worktree_dialog.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/operations/toast_overlay.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/operations.dart';

void main() {
  testWidgets(
    'add worktree closes on a failed reload with one retryable message',
    (tester) async {
      const repo = RepoLocation(RepoId('repo'), 'C:/repo', 'repo');
      final write = _Write();
      var loads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gitWriteOperationsProvider.overrideWithValue(write),
            operationsProvider.overrideWith(
              (ref) => OperationsNotifier(InMemoryActivityLog()),
            ),
            sidebarDataProvider.overrideWith((ref, repo) {
              loads++;
              return loads == 1
                  ? Future.value(SidebarData([], [], [], [], [], []))
                  : Future<SidebarData>.error(
                      StateError('git worktree list failed'),
                    );
            }),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: [AppPalette.dark()]),
            home: Scaffold(
              body: Stack(
                children: [
                  Consumer(
                    builder: (context, ref, child) {
                      ref.watch(sidebarDataProvider(repo));
                      return TextButton(
                        onPressed: () => AddWorktreeDialog.show(context, repo),
                        child: const Text('Add'),
                      );
                    },
                  ),
                  const ToastOverlay(),
                ],
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
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(loads, 2, reason: 'the sidebar was asked to reload');
      expect(
        find.text('Add worktree'),
        findsNothing,
        reason: 'the worktree exists, so the dialog behaves as on success',
      );
      expect(find.text(refreshFailureMessage), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      final ops = ProviderScope.containerOf(
        tester.element(find.byType(ToastOverlay)),
        listen: false,
      ).read(operationsProvider);
      expect(
        ops.where((o) => o.errorMessage == refreshFailureMessage),
        hasLength(1),
      );
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
