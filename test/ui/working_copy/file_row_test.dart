import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/file_row.dart';
import 'package:gitopen/ui/working_copy/state_badge.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

class _FakeWrite implements GitWriteOperations {
  final staged = <String>[];
  final unstaged = <String>[];
  final stagedPatches = <String>[];
  final unstagedPatches = <String>[];

  @override
  Future<GitResult<void>> stageFiles(RepoLocation r, List<String> paths) async {
    staged.addAll(paths);
    return const GitSuccess(null);
  }

  @override
  Future<GitResult<void>> unstageFiles(
    RepoLocation r,
    List<String> paths,
  ) async {
    unstaged.addAll(paths);
    return const GitSuccess(null);
  }

  @override
  Future<GitResult<void>> stagePatch(RepoLocation r, String unifiedDiff) async {
    stagedPatches.add(unifiedDiff);
    return const GitSuccess(null);
  }

  @override
  Future<GitResult<void>> unstagePatch(
    RepoLocation r,
    String unifiedDiff,
  ) async {
    unstagedPatches.add(unifiedDiff);
    return const GitSuccess(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

const _stagedDiff = FileDiff(
  path: 'lib/app.dart',
  changeKind: FileChangeKind.modified,
  isBinary: false,
  linesAdded: 1,
  linesDeleted: 1,
  hunks: [
    DiffHunk(
      oldStart: 1,
      oldCount: 1,
      newStart: 1,
      newCount: 1,
      header: '@@ -1,1 +1,1 @@',
      lines: [
        DiffLine(kind: DiffLineKind.deletion, content: 'old', oldLine: 1),
        DiffLine(kind: DiffLineKind.addition, content: 'new', newLine: 1),
      ],
    ),
  ],
);

const _modified = WorkingFileEntry(
  path: 'lib/app.dart',
  indexState: WorkingFileState.unmodified,
  workingTreeState: WorkingFileState.modified,
);

Widget _host(_FakeWrite write, {required bool isStaged}) => ProviderScope(
  overrides: [gitWriteOperationsProvider.overrideWithValue(write)],
  child: MaterialApp(
    theme: ThemeData(extensions: [AppPalette.dark()]),
    home: Scaffold(
      body: FileRow(
        repo: RepoLocation(RepoId.newId(), 'unused', 't'),
        entry: _modified,
        isStaged: isStaged,
      ),
    ),
  ),
);

void main() {
  testWidgets('renders the path and the expand chevron for unstaged rows', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeWrite(), isStaged: false));
    expect(find.text('lib/app.dart'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
  });

  testWidgets('checkbox stages the file on an unstaged row', (tester) async {
    final write = _FakeWrite();
    await tester.pumpWidget(_host(write, isStaged: false));
    await tester.tap(find.byIcon(Icons.check_box_outline_blank));
    await tester.pumpAndSettle();
    expect(write.staged, ['lib/app.dart']);
    expect(write.unstaged, isEmpty);
  });

  testWidgets('checkbox unstages the file on a staged row', (tester) async {
    final write = _FakeWrite();
    await tester.pumpWidget(_host(write, isStaged: true));
    // Staged rows show a filled checkbox and no expand chevron.
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    await tester.tap(find.byIcon(Icons.check_box));
    await tester.pumpAndSettle();
    expect(write.unstaged, ['lib/app.dart']);
    expect(write.staged, isEmpty);
  });

  testWidgets('discard action keeps its tooltip and button semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(
          body: DiscardIconButton(isSelected: false, onPressed: () {}),
        ),
      ),
    );

    expect(find.byTooltip('Discard changes'), findsOneWidget);
    final semantics = tester.getSemantics(
      find.bySemanticsLabel('Discard changes'),
    );
    expect(semantics.flagsCollection.isButton, isTrue);
  });

  testWidgets('staged row expands and unstages a hunk via the inline action', (
    tester,
  ) async {
    final write = _FakeWrite();
    final repo = RepoLocation(RepoId.newId(), 'unused', 't');
    const stagedEntry = WorkingFileEntry(
      path: 'lib/app.dart',
      indexState: WorkingFileState.modified,
      workingTreeState: WorkingFileState.unmodified,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitWriteOperationsProvider.overrideWithValue(write),
          stagedFileDiffProvider(
            (repo, 'lib/app.dart'),
          ).overrideWith((ref) async => _stagedDiff),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: FileRow(repo: repo, entry: stagedEntry, isStaged: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A staged, modified row is now expandable.
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Unstage hunk'));
    await tester.pumpAndSettle();

    expect(write.unstagedPatches, hasLength(1));
    expect(write.unstagedPatches.single, contains('-old'));
    expect(write.unstaged, isEmpty); // whole-file unstage was NOT used
  });

  testWidgets('unstaged row offers Stage and Discard for a selected hunk', (
    tester,
  ) async {
    final write = _FakeWrite();
    final repo = RepoLocation(RepoId.newId(), 'unused', 't');
    const entry = WorkingFileEntry(
      path: 'lib/app.dart',
      indexState: WorkingFileState.unmodified,
      workingTreeState: WorkingFileState.modified,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitWriteOperationsProvider.overrideWithValue(write),
          unstagedFileDiffProvider(
            (repo, 'lib/app.dart'),
          ).overrideWith((ref) async => _stagedDiff),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: FileRow(repo: repo, entry: entry, isStaged: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    // Tapping the hunk header selects the whole hunk.
    await tester.tap(find.text('@@ -1,1 +1,1 @@'));
    await tester.pumpAndSettle();

    expect(find.text('Stage selected hunks'), findsOneWidget);
    expect(find.text('Discard selected hunks'), findsOneWidget);
  });
}
