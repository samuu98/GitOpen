import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git_lfs/git_lfs_models.dart';
import 'package:gitopen/application/git_lfs/git_lfs_operations.dart';
import 'package:gitopen/application/git_lfs/git_lfs_service.dart';
import 'package:gitopen/application/operations/activity_log_store.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/lfs/lfs_panel.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('second LFS transfer tap is disabled while busy', (
    tester,
  ) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    final stream = StreamController<GitProgress>();
    final lfs = _PendingLfs(stream.stream);
    final ops = OperationsNotifier(_ActivityStore());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitLfsServiceProvider.overrideWithValue(
            GitLfsService(
              lfs: lfs,
              resolveProfile: (_) async => null,
              errorText: (e) => e.toString(),
            ),
          ),
          operationsProvider.overrideWith((ref) => ops),
          gitLfsStatusProvider.overrideWith(
            (ref, repo) async => const GitLfsStatus(
              isInstalled: true,
              version: '3.6.1',
              isRepoConfigured: true,
              hasAttributes: true,
            ),
          ),
          gitLfsTrackedPatternsProvider.overrideWith((ref, repo) async => []),
          gitLfsFilesProvider.overrideWith((ref, repo) async => []),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 500,
              child: LfsPanel(repo: repo),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch'));
    await tester.pump();
    expect(lfs.calls, 1);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Pull'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Fetch'), warnIfMissed: false);
    await tester.pump();
    expect(lfs.calls, 1);
    await stream.close();
    await tester.pumpAndSettle();
    expect(ops.state.first.status, OperationStatus.success);
  });

  testWidgets('shows not-installed state', (tester) async {
    await _pumpLfs(
      tester,
      status: const GitLfsStatus(
        isInstalled: false,
        version: null,
        isRepoConfigured: false,
        hasAttributes: false,
      ),
    );

    expect(find.text('Git LFS is not installed'), findsOneWidget);
  });

  testWidgets(
    'shows repo setup action when LFS is installed but not configured',
    (tester) async {
      await _pumpLfs(
        tester,
        status: const GitLfsStatus(
          isInstalled: true,
          version: '3.6.1',
          isRepoConfigured: false,
          hasAttributes: false,
        ),
      );

      expect(find.text('Install in repo'), findsOneWidget);
    },
  );

  testWidgets('shows tracked patterns and files when ready', (tester) async {
    await _pumpLfs(
      tester,
      status: const GitLfsStatus(
        isInstalled: true,
        version: '3.6.1',
        isRepoConfigured: true,
        hasAttributes: true,
      ),
      patterns: const [
        GitLfsTrackedPattern(
          pattern: '*.bin',
          attributes: 'filter=lfs diff=lfs merge=lfs -text',
          source: '.gitattributes',
        ),
      ],
      files: const [
        GitLfsFile(
          oid: 'abcdef123456',
          path: 'assets/big.bin',
          sizeLabel: '12 MB',
        ),
      ],
    );

    expect(find.text('*.bin'), findsOneWidget);
    expect(find.text('assets/big.bin'), findsOneWidget);
    expect(find.text('12 MB'), findsOneWidget);
    expect(find.byTooltip('Add pattern'), findsOneWidget);
  });

  testWidgets('shows empty patterns and files messages when ready', (
    tester,
  ) async {
    await _pumpLfs(
      tester,
      status: const GitLfsStatus(
        isInstalled: true,
        version: '3.6.1',
        isRepoConfigured: true,
        hasAttributes: true,
      ),
    );

    expect(find.text('No tracked patterns'), findsOneWidget);
    expect(find.text('No LFS files in this repository'), findsOneWidget);
  });
}

final class _PendingLfs implements GitLfsOperations {
  _PendingLfs(this.stream);
  final Stream<GitProgress> stream;
  int calls = 0;

  @override
  Stream<GitProgress> fetch(RepoLocation repo, {AuthSpec? auth}) {
    calls++;
    return stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

final class _ActivityStore implements ActivityLogStore {
  @override
  Future<void> upsert(RunningOperation operation) async {}

  @override
  Future<List<RunningOperation>> recent({int limit = 50}) async => [];

  @override
  Future<void> clearCompleted() async {}
}

Future<void> _pumpLfs(
  WidgetTester tester, {
  required GitLfsStatus status,
  List<GitLfsTrackedPattern> patterns = const [],
  List<GitLfsFile> files = const [],
}) async {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitLfsStatusProvider.overrideWith((ref, repo) async => status),
        gitLfsTrackedPatternsProvider.overrideWith(
          (ref, repo) async => patterns,
        ),
        gitLfsFilesProvider.overrideWith((ref, repo) async => files),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(
          body: SizedBox(width: 800, height: 500, child: LfsPanel(repo: repo)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
