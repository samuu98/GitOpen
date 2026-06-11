import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/files/file_tree_entry.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/file_tree_view.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final class _FakeReadOps implements GitReadOperations {
  @override
  Future<List<FileTreeEntry>> getFileTree(
    RepoLocation repo,
    CommitSha sha,
    String path, {
    bool recursive = false,
  }) async {
    expect(recursive, isTrue);
    return const [
      FileTreeEntry(
        name: 'deep.txt',
        fullPath: 'dir/sub/deep.txt',
        kind: FileTreeKind.blob,
        sizeBytes: 2,
      ),
      FileTreeEntry(
        name: 'root.txt',
        fullPath: 'root.txt',
        kind: FileTreeKind.blob,
        sizeBytes: 2,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _FakeSettingsStore implements SettingsStore {
  _FakeSettingsStore(this.seed);
  final Map<String, dynamic> seed;

  @override
  Future<Map<String, dynamic>> readAll() async => seed;

  @override
  Future<void> put(String key, dynamic value) async {}
}

Future<void> _pump(WidgetTester tester, {required bool asTree}) async {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(_FakeReadOps()),
        appSettingsProvider.overrideWith(
          (ref) => AppSettingsNotifier(
            _FakeSettingsStore({'file_lists_as_tree': asTree}),
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 400,
            child: FileTreeViewWidget(repo: repo, sha: CommitSha('a' * 40)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tree mode folds the recursive listing', (tester) async {
    await _pump(tester, asTree: true);
    expect(find.text('dir/sub'), findsOneWidget); // compressed chain
    expect(find.text('deep.txt'), findsOneWidget);
    expect(find.text('root.txt'), findsOneWidget);
    expect(find.text('dir/sub/deep.txt'), findsNothing);
  });

  testWidgets('flat mode lists full paths', (tester) async {
    await _pump(tester, asTree: false);
    expect(find.text('dir/sub/deep.txt'), findsOneWidget);
    expect(find.text('root.txt'), findsOneWidget);
    expect(find.text('dir/sub'), findsNothing);
  });
}
