import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/commit_details_view.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import '../../_helpers/diff_view_harness.dart';

final class _FakeReadOps implements GitReadOperations {
  _FakeReadOps(this.diff, this.commit);
  final DiffResult diff;
  final CommitInfo commit;

  @override
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query) =>
      Stream.value(commit);

  @override
  Future<String?> getCommitFullMessage(
    RepoLocation repo,
    CommitSha sha,
  ) async => commit.message;

  @override
  Future<DiffResult> getDiff(
    RepoLocation repo,
    DiffSpec spec, {
    bool ignoreWhitespace = false,
  }) async => diff;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  testWidgets('lists changed files and a click jumps to the diff',
      (tester) async {
    final diff = diffOf([
      fileDiffFixture('lib/a.dart'),
      fileDiffFixture('lib/b.dart'),
    ]);
    final sig = CommitSignature('Test', 'test@example.com', DateTime(2026));
    final commit = CommitInfo(
      sha: CommitSha('a' * 40),
      parentShas: const [],
      author: sig,
      committer: sig,
      summary: 'My commit',
      message: 'My commit',
    );
    final container = ProviderContainer(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(
          _FakeReadOps(diff, commit),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: CommitDetailsView(
                repo: testRepo(),
                sha: CommitSha('a' * 40),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Files changed (2)'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('lib/b.dart'), findsOneWidget);

    await tester.tap(find.text('lib/b.dart'));
    await tester.pumpAndSettle();

    expect(container.read(bottomPanelTabProvider), 'changes');
    expect(container.read(revealFilePathProvider), 'lib/b.dart');
  });
}
