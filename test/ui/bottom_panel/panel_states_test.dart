import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/files/file_tree_entry.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/commit_details_view.dart';
import 'package:gitopen/ui/bottom_panel/diff_view.dart';
import 'package:gitopen/ui/bottom_panel/file_tree_view.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/common/app_panel_state.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final class _ReadOps implements GitReadOperations {
  int calls = 0;

  @override
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query) {
    calls++;
    return Stream.error(StateError('commit unavailable'));
  }

  @override
  Future<DiffResult> getDiff(
    RepoLocation repo,
    DiffSpec spec, {
    bool ignoreWhitespace = false,
  }) async {
    calls++;
    if (calls == 1) throw StateError('diff unavailable');
    return const DiffResult(files: []);
  }

  @override
  Future<List<FileTreeEntry>> getFileTree(
    RepoLocation repo,
    CommitSha sha,
    String path, {
    bool recursive = false,
  }) async {
    calls++;
    if (calls == 1) throw StateError('tree unavailable');
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _SettingsStore implements SettingsStore {
  @override
  Future<Map<String, dynamic>> readAll() async => {};

  @override
  Future<void> put(String key, dynamic value) async {}
}

void main() {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
  final sha = CommitSha('a' * 40);

  for (final (name, build) in <(String, Widget Function())>[
    ('commit details', () => CommitDetailsView(repo: repo, sha: sha)),
    ('diff', () => DiffView(repo: repo, sha: sha)),
    ('file tree', () => FileTreeViewWidget(repo: repo, sha: sha)),
  ]) {
    testWidgets('$name shows detail loading, error, and retry', (tester) async {
      final ops = _ReadOps();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gitReadOperationsProvider.overrideWithValue(ops),
            appSettingsProvider.overrideWith(
              (ref) => AppSettingsNotifier(_SettingsStore()),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: [AppPalette.dark()]),
            home: Scaffold(
              body: SizedBox(width: 800, height: 500, child: build()),
            ),
          ),
        ),
      );
      expect(find.byType(AppLoadingState), findsOneWidget);
      await tester.pump();
      await tester.pump();
      expect(find.byType(AppErrorState), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(ops.calls, 2);
      if (name != 'commit details') {
        await tester.pump();
        expect(find.byType(AppEmptyState), findsOneWidget);
      }
    });
  }
}
