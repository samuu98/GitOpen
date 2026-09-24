import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/operations/blocking_overlay.dart';
import 'package:gitopen/ui/operations/toast_overlay.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/operations.dart';

/// Read side under the test's control.
class _FakeRead implements GitReadOperations {
  int statusCalls = 0;

  @override
  Future<RepoStatus> getStatus(RepoLocation repo) async {
    statusCalls++;
    return const RepoStatus(isDetached: false, isBare: false, entries: []);
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

/// Stands in for the commit-graph load (the real one lays out in an isolate,
/// which a widget test cannot drive). The first load resolves at once; every
/// reload hangs until [release], so a test can hold the graph "still
/// reloading" after git has already exited.
class _FakeGraph {
  _FakeGraph({this.failReload = false});

  final bool failReload;
  int loads = 0;
  Completer<void> gate = Completer<void>();

  Future<GraphData> load() async {
    loads++;
    if (loads > 1) await gate.future;
    if (loads > 1 && failReload) throw StateError('git log failed');
    return GraphData(const [], const {}, 0, hasMore: false);
  }

  void release() {
    if (!gate.isCompleted) gate.complete();
  }
}

void main() {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'test');

  ProviderContainer containerFor(_FakeRead read, [_FakeGraph? graph]) {
    final container = ProviderContainer(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(read),
        operationsProvider.overrideWith(
          (ref) => OperationsNotifier(InMemoryActivityLog()),
        ),
        if (graph != null)
          commitGraphDataProvider(repo).overrideWith((ref) => graph.load()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// The blocking spinner (and the toast's ticker) schedule frames forever, so
  /// `pumpAndSettle` can never be used once an indicator is up: pump until the
  /// condition the test cares about holds.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 300; i++) {
      if (done()) return;
      await tester.pump(const Duration(milliseconds: 20));
    }
    fail('condition never held while pumping');
  }

  Future<void> pumpWindow(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Lets the indicator's minimum-visible timer expire so the test does not
  /// end with it pending.
  Future<void> settleIndicator(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 600));

  /// Watches the two views a fetch affects, with the real overlays on top.
  Future<void> pumpShell(
    WidgetTester tester,
    ProviderContainer container, {
    bool withToast = false,
  }) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Stack(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final graph = ref.watch(commitGraphDataProvider(repo));
                    final status = ref.watch(repoStatusProvider(repo));
                    return Text(
                      'graph:${graph.isLoading} status:${status.isLoading}',
                    );
                  },
                ),
                if (withToast) const ToastOverlay(),
                const BlockingOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'busy stays visible until the graph resolves, not when git exits',
    (tester) async {
      final read = _FakeRead();
      final graph = _FakeGraph();
      final container = containerFor(read, graph);
      await pumpShell(tester, container);
      await tester.pumpAndSettle();
      expect(graph.loads, 1);

      final gitDone = Completer<void>();
      final run = container
          .read(actionRunnerProvider)
          .runAndRefresh<void>(
            key: 'fetch',
            repo: repo,
            label: 'Fetching origin',
            scopes: const {RefreshScope.status, RefreshScope.graph},
            action: () => gitDone.future,
          );

      // Below the show delay: no indicator at all (no flicker).
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Fetching origin'), findsNothing);

      // git exits — the graph reload has only just started.
      gitDone.complete();
      await tester.pump(const Duration(milliseconds: 100));
      expect(graph.loads, 2, reason: 'the graph re-logs');
      expect(find.text('Fetching origin'), findsOneWidget);
      expect(container.read(busyProvider).isBusy, isTrue);
      expect(find.text('graph:true status:false'), findsOneWidget);

      // Still nothing resolved: busy must not end here.
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(busyProvider).isBusy, isTrue);

      graph.release();
      await pumpUntil(tester, () => !container.read(busyProvider).isBusy);
      final result = await run;
      expect(result.status, ActionRunStatus.succeeded);
      expect(
        container.read(commitGraphDataProvider(repo)).hasValue,
        isTrue,
        reason: 'busy ended only once the graph had its new data',
      );
      await settleIndicator(tester);
    },
  );

  testWidgets('a reload error after git success reads as a refresh failure', (
    tester,
  ) async {
    final read = _FakeRead();
    final graph = _FakeGraph(failReload: true);
    final container = containerFor(read, graph);
    await pumpShell(tester, container, withToast: true);
    await pumpWindow(tester);

    final ops = container.read(operationsProvider.notifier);
    final opId = ops.start(OpKind.fetch, 'Fetching origin', repo: repo);

    final run = container
        .read(actionRunnerProvider)
        .runAndRefresh<String>(
          key: 'fetch',
          repo: repo,
          scopes: const {RefreshScope.status, RefreshScope.graph},
          action: () async => opId,
          operationId: (id) => id,
        );
    await tester.pump(const Duration(milliseconds: 200));
    graph.release();
    await pumpUntil(tester, () => !container.read(busyProvider).isBusy);
    await tester.pump();

    final result = await run;
    expect(result.status, ActionRunStatus.refreshFailed);
    final op = container
        .read(operationsProvider)
        .firstWhere(
          (o) => o.id == opId,
        );
    expect(op.status, OperationStatus.failed);
    expect(op.errorMessage, refreshFailureMessage);
    expect(op.onRetry, isNotNull, reason: 'the refresh can be retried');
    expect(find.text(refreshFailureMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(container.read(busyProvider).isBusy, isFalse);
    await settleIndicator(tester);
  });

  testWidgets('a second submit while the action runs does not start a second', (
    tester,
  ) async {
    final read = _FakeRead();
    final container = containerFor(read);
    await pumpShell(tester, container);
    await pumpWindow(tester);

    var calls = 0;
    final gate = Completer<void>();
    final runner = container.read(actionRunnerProvider);
    Future<ActionRun<void>> submit() => runner.runAndRefresh<void>(
      key: 'branch-delete:feature',
      repo: repo,
      scopes: const {RefreshScope.status},
      action: () {
        calls++;
        return gate.future;
      },
    );

    final first = submit();
    await tester.pump();
    final second = await submit();
    expect(calls, 1);
    expect(second.status, ActionRunStatus.skipped);
    expect(second.ran, isFalse);

    gate.complete();
    await pumpUntil(tester, () => !container.read(busyProvider).isBusy);
    expect((await first).status, ActionRunStatus.succeeded);
    await settleIndicator(tester);
  });

  testWidgets('a completion after a repository switch is ignored', (
    tester,
  ) async {
    final read = _FakeRead();
    final graph = _FakeGraph();
    final container = containerFor(read, graph);
    await pumpShell(tester, container);
    await pumpWindow(tester);
    container.read(activeWorkspaceIdProvider.notifier).state = repo.id;
    final statusBefore = read.statusCalls;
    final graphBefore = graph.loads;

    final gate = Completer<void>();
    final run = container
        .read(actionRunnerProvider)
        .runAndRefresh<void>(
          key: 'fetch',
          repo: repo,
          scopes: const {RefreshScope.status, RefreshScope.graph},
          action: () => gate.future,
        );
    await tester.pump();

    // The user opened another repository while git was still running.
    container.read(activeWorkspaceIdProvider.notifier).state = RepoId.newId();
    gate.complete();
    await pumpUntil(tester, () => !container.read(busyProvider).isBusy);

    final result = await run;
    expect(result.status, ActionRunStatus.stale);
    expect(read.statusCalls, statusBefore, reason: 'no refresh of a dead repo');
    expect(graph.loads, graphBefore);
    expect(container.read(busyProvider).isBusy, isFalse);
    await settleIndicator(tester);
  });

  testWidgets('overlapping runs leave no active refresh once both settle', (
    tester,
  ) async {
    final read = _FakeRead();
    final container = containerFor(read);
    final runner = container.read(actionRunnerProvider);
    final first = Completer<void>();
    final second = Completer<void>();
    final a = runner.runAndRefresh<void>(
      key: 'fetch',
      repo: repo,
      scopes: const {RefreshScope.graph},
      action: () => first.future,
    );
    final b = runner.runAndRefresh<void>(
      key: 'stash-save',
      repo: repo,
      scopes: const {RefreshScope.workingCopy},
      action: () => second.future,
    );
    await tester.pump();
    expect(runner.activeRefresh!.covered, {
      RepoRefreshScope.refs,
      RepoRefreshScope.worktree,
    });

    // The older run finishes first; the newer one must not resurrect it.
    first.complete();
    await a;
    expect(runner.activeRefresh!.covered, {RepoRefreshScope.worktree});
    second.complete();
    await b;
    expect(runner.activeRefresh, isNull);
    await settleIndicator(tester);
  });

  testWidgets('a view nobody has open is not awaited', (tester) async {
    final read = _FakeRead();
    final graph = _FakeGraph();
    final container = containerFor(read, graph);
    // No shell: nothing watches the graph, so no git log may be spawned.
    final result = await container
        .read(actionRunnerProvider)
        .runAndRefresh<void>(
          key: 'tag-delete:v1',
          repo: repo,
          scopes: const {RefreshScope.status, RefreshScope.graph},
          action: () async {},
        );
    expect(result.status, ActionRunStatus.succeeded);
    expect(graph.loads, 0);
    expect(read.statusCalls, 0);
  });
}
