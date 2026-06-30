import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git_lfs/git_lfs_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/shell/view_selector.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

RepoStatus _statusWith(int n) => RepoStatus(
      isDetached: false,
      isBare: false,
      currentBranch: 'main',
      entries: [
        for (var i = 0; i < n; i++)
          WorkingFileEntry(
            path: 'file_$i.dart',
            indexState: WorkingFileState.unmodified,
            workingTreeState: WorkingFileState.modified,
          ),
      ],
    );

/// Hosts [ViewSelector] with the three providers it reads stubbed so the test
/// stays off the `git` CLI: only the working-tree count varies.
Widget _host(RepoLocation repo, int changedCount) {
  return ProviderScope(
    overrides: [
      repoStatusProvider(repo)
          .overrideWith((_) async => _statusWith(changedCount)),
      githubSlugProvider(repo).overrideWith((_) async => null),
      gitLfsStatusProvider(repo).overrideWith(
        (_) async => const GitLfsStatus(
          isInstalled: false,
          version: null,
          isRepoConfigured: false,
          hasAttributes: false,
        ),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(body: ViewSelector(repo: repo)),
    ),
  );
}

void main() {
  testWidgets('Changes tab shows a count badge when files are changed',
      (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    await tester.pumpWidget(_host(repo, 3));
    // Let the stubbed futures resolve so the count is read.
    await tester.pump();
    await tester.pump();

    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('Changes tab shows no badge when the working tree is clean',
      (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    await tester.pumpWidget(_host(repo, 0));
    await tester.pump();
    await tester.pump();

    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}
