import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/application/watch/repo_watcher.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/auto_refresh/repo_auto_refresh_scope.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

class _FakeWatcher implements RepoWatcher {
  final controller = StreamController<RepoChange>.broadcast();
  int active = 0;

  @override
  Stream<RepoChange> changes(RepoLocation repo) {
    final single = StreamController<RepoChange>()
      ..onListen = (() => active++)
      ..onCancel = (() async => active--);
    controller.stream.listen(single.add, onDone: single.close);
    return single.stream;
  }
}

/// Counts the actual git work: a status reload is a [getStatus] call; a graph
/// re-log is a [getCommits] call. That is exactly what scoping changes.
class _CountingRead implements GitReadOperations {
  int statusCalls = 0;
  int commitsCalls = 0;

  @override
  Future<RepoStatus> getStatus(RepoLocation repo) async {
    statusCalls++;
    return RepoStatus(isDetached: false, isBare: false, entries: [
      WorkingFileEntry(
        path: 'change$statusCalls.txt',
        indexState: WorkingFileState.unmodified,
        workingTreeState: WorkingFileState.modified,
      ),
    ]);
  }

  @override
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query) {
    commitsCalls++;
    return const Stream<CommitInfo>.empty();
  }

  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) async => const [];
  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) async => const [];
  @override
  Future<List<Branch>> getBranches(RepoLocation repo) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not faked');
}

class _InMemoryStore implements SettingsStore {
  final Map<String, dynamic> values = {};
  @override
  Future<Map<String, dynamic>> readAll() async => values;
  @override
  Future<void> put(String key, dynamic value) async => values[key] = value;
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    _FakeWatcher watcher,
    _CountingRead read,
    RepoLocation repo,
  ) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repoWatcherProvider.overrideWithValue(watcher),
        gitReadOperationsProvider.overrideWithValue(read),
        appSettingsProvider
            .overrideWith((ref) => AppSettingsNotifier(_InMemoryStore())),
      ],
      child: MaterialApp(
        home: RepoAutoRefreshScope(
          repo: repo,
          child: Column(children: [
            Consumer(builder: (context, ref, _) {
              final status = ref.watch(repoStatusProvider(repo)).value;
              return Text('status:${status?.entries.first.path}');
            }),
            Consumer(builder: (context, ref, _) {
              final entries = ref.watch(workingCopyStatusProvider(repo)).value;
              return Text('entries:${entries?.first.path}');
            }),
            Consumer(builder: (context, ref, _) {
              ref.watch(commitGraphDataProvider(repo));
              return const SizedBox();
            }),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('mergeState event reloads status but NOT the graph',
      (tester) async {
    final watcher = _FakeWatcher();
    final read = _CountingRead();
    final repo = RepoLocation(RepoId.newId(), 'unused', 't');
    await pump(tester, watcher, read, repo);
    final statusBase = read.statusCalls;
    final commitsBase = read.commitsCalls;

    watcher.controller.add(RepoChange.mergeState);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(read.statusCalls, greaterThan(statusBase)); // status reloaded
    expect(read.commitsCalls, commitsBase); // graph NOT re-logged
    await watcher.controller.close();
  });

  testWidgets('one status call feeds entries and status on each refresh',
      (tester) async {
    final watcher = _FakeWatcher();
    final read = _CountingRead();
    final repo = RepoLocation(RepoId.newId(), 'unused', 't');
    await pump(tester, watcher, read, repo);
    expect(read.statusCalls, 1);
    expect(find.text('status:change1.txt'), findsOneWidget);
    expect(find.text('entries:change1.txt'), findsOneWidget);

    watcher.controller.add(RepoChange.mergeState);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(read.statusCalls, 2);
    expect(find.text('status:change2.txt'), findsOneWidget);
    expect(find.text('entries:change2.txt'), findsOneWidget);
    await watcher.controller.close();
  });

  testWidgets('head event reloads both status and graph', (tester) async {
    final watcher = _FakeWatcher();
    final read = _CountingRead();
    final repo = RepoLocation(RepoId.newId(), 'unused', 't');
    await pump(tester, watcher, read, repo);
    final statusBase = read.statusCalls;
    final commitsBase = read.commitsCalls;

    watcher.controller.add(RepoChange.head);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(read.statusCalls, greaterThan(statusBase));
    expect(read.commitsCalls, greaterThan(commitsBase));
    await watcher.controller.close();
  });

  testWidgets('watcher events join an action refresh instead of doubling it',
      (tester) async {
    final watcher = _FakeWatcher();
    final read = _CountingRead();
    final repo = RepoLocation(RepoId.newId(), 'unused', 't');
    await pump(tester, watcher, read, repo);
    final statusBase = read.statusCalls;

    // A git action is running: its refresh already covers the worktree.
    final gate = Completer<void>();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RepoAutoRefreshScope)),
    );
    final run = container.read(actionRunnerProvider).runAndRefresh<void>(
      key: 'merge:feature',
      repo: repo,
      scopes: const {RefreshScope.status},
      action: () => gate.future,
    );
    await tester.pump();
    // The write moved .git, so the watcher fires for the same data.
    watcher.controller.add(RepoChange.mergeState);
    await tester.pump(const Duration(milliseconds: 500));
    expect(read.statusCalls, statusBase, reason: 'the watcher waits');

    gate.complete();
    await tester.pump();
    await tester.pump();
    await run;
    expect(read.statusCalls, statusBase + 1, reason: 'one refresh, not two');

    // Watching resumes normally afterwards.
    watcher.controller.add(RepoChange.mergeState);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(read.statusCalls, statusBase + 2);
    await watcher.controller.close();
  });

  testWidgets('autoRefresh off → subscription settles to none', (tester) async {
    final watcher = _FakeWatcher();
    final repo = RepoLocation(RepoId.newId(), 'unused', 't');
    final store = _InMemoryStore()..values['auto_refresh'] = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repoWatcherProvider.overrideWithValue(watcher),
        gitReadOperationsProvider.overrideWithValue(_CountingRead()),
        appSettingsProvider.overrideWith((ref) => AppSettingsNotifier(store)),
      ],
      child: MaterialApp(
        home: RepoAutoRefreshScope(repo: repo, child: const SizedBox()),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(watcher.active, 0);
    await watcher.controller.close();
  });
}
