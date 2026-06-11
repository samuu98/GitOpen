import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/interactive_rebase_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

CommitInfo _commit(String shaChar, String summary) {
  final sig = CommitSignature('Ada', 'a@x.io', DateTime.utc(2026, 6));
  return CommitInfo(
    sha: CommitSha(shaChar * 40),
    parentShas: const [],
    author: sig,
    committer: sig,
    summary: summary,
    message: '$summary\n\nbody of $summary',
  );
}

final class _FakeReadOps implements GitReadOperations {
  // Newest-first, like `git log`.
  final List<CommitInfo> commits = [
    _commit('b', 'second'),
    _commit('a', 'first'),
  ];

  @override
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query) =>
      Stream.fromIterable(commits);

  @override
  Future<String?> getCommitFullMessage(
    RepoLocation repo,
    CommitSha sha,
  ) async => 'original message of ${sha.short()}';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  List<RebaseTodoEntry>? result;

  Future<void> pump(WidgetTester tester) async {
    result = null;
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitReadOperationsProvider.overrideWithValue(_FakeReadOps()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await InteractiveRebaseDialog.show(
                      context,
                      repo: repo,
                      onto: CommitSha('0' * 40),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Opens the action dropdown on the row showing [commitSummary] and picks
  /// [action] from the menu.
  Future<void> selectAction(
    WidgetTester tester,
    String commitSummary,
    String action,
  ) async {
    final row = find.ancestor(
      of: find.text(commitSummary),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: row.first, matching: find.text('pick')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(action).last);
    await tester.pumpAndSettle();
  }

  testWidgets('reword shows a prefilled message editor and returns it', (
    tester,
  ) async {
    await pump(tester);
    await selectAction(tester, 'second', 'reword');

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    expect(
      tester.widget<TextField>(field).controller!.text,
      contains('original message'),
    );

    await tester.enterText(field, 'second, reworded');
    await tester.tap(find.text('Start rebase'));
    await tester.pumpAndSettle();

    // Returned oldest-first: [first(pick), second(reword + message)].
    expect(result, isNotNull);
    expect(result!.length, 2);
    expect(result![0].action, RebaseTodoAction.pick);
    expect(result![1].action, RebaseTodoAction.reword);
    expect(result![1].message, 'second, reworded');
  });

  testWidgets('a fold-first plan blocks Start with a validation message', (
    tester,
  ) async {
    await pump(tester);
    // 'first' is the OLDEST commit (bottom row) — folding it is invalid.
    await selectAction(tester, 'first', 'squash');

    expect(find.textContaining('cannot fold'), findsOneWidget);
    final button = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Start rebase'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('drag handles render one per row', (tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));
  });
}
