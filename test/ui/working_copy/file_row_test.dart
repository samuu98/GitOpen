import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/file_row.dart';

class _FakeWrite implements GitWriteOperations {
  final staged = <String>[];
  final unstaged = <String>[];

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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

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
}
