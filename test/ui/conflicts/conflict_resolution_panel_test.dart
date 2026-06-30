import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/conflicts/conflict_resolution_panel.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

const _conflictText = '<<<<<<< HEAD\n'
    'ours\n'
    '=======\n'
    'theirs\n'
    '>>>>>>> feature\n';

/// Read port that reports the given paths as conflicted and serves canned
/// working-tree content, keeping the panel off the `git` CLI and off disk.
class _FakeRead implements GitReadOperations {
  _FakeRead(this.conflictedPaths, this.fileContent);
  final List<String> conflictedPaths;
  final String fileContent;

  @override
  Future<RepoStatus> getStatus(RepoLocation repo) async => RepoStatus(
        isDetached: false,
        isBare: false,
        currentBranch: 'main',
        entries: [
          for (final p in conflictedPaths)
            WorkingFileEntry(
              path: p,
              indexState: WorkingFileState.unmodified,
              workingTreeState: WorkingFileState.conflicted,
            ),
        ],
      );

  @override
  Future<String> readWorkingFile(
    RepoLocation repo,
    String relativePath,
  ) async =>
      fileContent;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

Widget _host(RepoLocation repo, _FakeRead read) {
  return ProviderScope(
    overrides: [
      repoStateProvider(repo).overrideWith((_) async => InProgressOp.merge),
      gitReadOperationsProvider.overrideWithValue(read),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 600,
          child: ConflictResolutionPanel(repo: repo),
        ),
      ),
    ),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 60,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  testWidgets('single conflict auto-expands to the inline 3-way editor',
      (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    await tester.pumpWidget(
      _host(repo, _FakeRead(['lib/app.dart'], _conflictText)),
    );

    await _pumpUntil(tester, find.text('Merge in progress — 1 conflict'));
    expect(find.text('lib/app.dart'), findsOneWidget);

    // The lone conflict starts expanded, so the inline resolver — not just the
    // file row — is on screen.
    await _pumpUntil(tester, find.text('Use ours'));
    expect(find.text('ours'), findsOneWidget);
    expect(find.text('theirs'), findsOneWidget);
    expect(find.text('Use ours'), findsOneWidget);
    expect(find.text('Use theirs'), findsOneWidget);
  });

  testWidgets('multiple conflicts render collapsed cards', (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    await tester.pumpWidget(
      _host(repo, _FakeRead(['a.dart', 'b.dart'], _conflictText)),
    );

    await _pumpUntil(tester, find.text('Merge in progress — 2 conflicts'));
    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('b.dart'), findsOneWidget);
    // Collapsed: no inline resolver content visible yet.
    expect(find.text('Use ours'), findsNothing);
  });
}
