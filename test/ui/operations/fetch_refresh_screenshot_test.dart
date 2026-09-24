import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/commit_graph/commit_node.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/operations/blocking_overlay.dart';
import 'package:gitopen/ui/operations/toast_overlay.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/operations.dart';
import '../../_helpers/screenshot.dart';

final _screenshots = PipelineScreenshotComparator('ux-l2-refresh');

CommitNode _node(String sha, String summary) => CommitNode(
  commit: CommitInfo(
    sha: CommitSha(sha),
    parentShas: const [],
    author: CommitSignature('Ada', 'ada@example.com', DateTime(2026, 9, 24)),
    committer: CommitSignature('Ada', 'ada@example.com', DateTime(2026, 9, 24)),
    summary: summary,
    message: summary,
  ),
  lane: 0,
  color: 0,
  topSegments: const [],
  bottomSegments: const [],
);

GraphData _graph(List<CommitNode> nodes) =>
    GraphData(nodes, const {}, 0, hasMore: false);

final _before = [
  _node('a1b2c3d', 'Add the refresh scope runner'),
  _node('b2c3d4e', 'Shared interaction states'),
];
final _after = [
  _node('f6e5d4c', 'Merge pull request #12 from origin/main'),
  _node('e5d4c3b', 'Bump the toast policy'),
  ..._before,
];

class _ShellRead implements GitReadOperations {
  @override
  Future<RepoStatus> getStatus(RepoLocation repo) async =>
      const RepoStatus(isDetached: false, isBare: false, entries: []);
  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) async => const [];
  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not faked');
}

/// The graph reload hangs until [release], so a frame can be captured while
/// git has already exited and the view has not caught up.
class _GatedGraph {
  _GatedGraph({this.fail = false});
  final bool fail;
  int loads = 0;
  final gate = Completer<void>();

  Future<GraphData> load() async {
    loads++;
    if (loads == 1) return _graph(_before);
    await gate.future;
    if (fail) throw StateError('git log failed');
    return _graph(_after);
  }

  void release() {
    if (!gate.isCompleted) gate.complete();
  }
}

String _graphHeader(AsyncValue<GraphData> graph) {
  if (graph.hasError) return 'Commit graph — failed to load';
  final count = graph.value?.nodes.length ?? 0;
  return 'Commit graph — $count commits'
      '${graph.isLoading ? ' (reloading)' : ''}';
}

class _Shell extends ConsumerWidget {
  const _Shell({required this.repo, required this.boundary});
  final RepoLocation repo;
  final Key boundary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final graph = ref.watch(commitGraphDataProvider(repo));
    return RepaintBoundary(
      key: boundary,
      child: ColoredBox(
        color: palette.bg1,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 38,
                  color: palette.bg0,
                  padding: EdgeInsets.symmetric(horizontal: spacing.md),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      for (final label in ['Fetch', 'Pull', 'Push', 'Stash'])
                        Padding(
                          padding: EdgeInsets.only(right: spacing.lg),
                          child: Text(
                            label,
                            style: TextStyle(color: palette.fg1, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 220,
                        child: ColoredBox(
                          color: palette.bg0,
                          child: Padding(
                            padding: EdgeInsets.all(spacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'BRANCHES',
                                  style: TextStyle(
                                    color: palette.fg2,
                                    fontSize: 11,
                                  ),
                                ),
                                SizedBox(height: spacing.sm),
                                for (final name in ['main', 'fix/ux'])
                                  Padding(
                                    padding: EdgeInsets.only(top: spacing.xs),
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        color: palette.fg0,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(spacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _graphHeader(graph),
                                style: TextStyle(
                                  color: palette.fg2,
                                  fontSize: 11,
                                ),
                              ),
                              SizedBox(height: spacing.sm),
                              for (final node
                                  in graph.value?.nodes ?? const <CommitNode>[])
                                Padding(
                                  padding: EdgeInsets.only(top: spacing.xs),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          node.commit.sha.value,
                                          style: TextStyle(
                                            color: palette.accentRemote,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        node.commit.summary,
                                        style: TextStyle(
                                          color: palette.fg0,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const ToastOverlay(),
            const BlockingOverlay(),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUpAll(loadAppFonts);

  final repo = RepoLocation(RepoId.newId(), 'unused', 'gitopen');

  ProviderContainer containerFor(_GatedGraph graph) {
    final container = ProviderContainer(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(_ShellRead()),
        operationsProvider.overrideWith(
          (ref) => OperationsNotifier(InMemoryActivityLog()),
        ),
        commitGraphDataProvider(repo).overrideWith((ref) => graph.load()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> shoot(WidgetTester tester, Key key, String name) async {
    await expectLater(find.byKey(key), matchesGoldenFile(name));
    expect(_screenshots.fileFor(name).existsSync(), isTrue);
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 300; i++) {
      if (done()) return;
      await tester.pump(const Duration(milliseconds: 20));
    }
    fail('condition never held while pumping');
  }

  Future<ProviderContainer> start(
    WidgetTester tester,
    _GatedGraph graph,
    Key key,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 620));
    final container = containerFor(graph);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(
            extensions: [AppPalette.dark(), const AppMotion.standard()],
          ),
          home: Scaffold(body: _Shell(repo: repo, boundary: key)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('renders the fetch lifecycle', (tester) async {
    final previous = goldenFileComparator;
    goldenFileComparator = _screenshots;
    addTearDown(() => goldenFileComparator = previous);
    final key = GlobalKey();
    final graph = _GatedGraph();
    final container = await start(tester, graph, key);

    final ops = container.read(operationsProvider.notifier);
    late String opId;
    final gitDone = Completer<void>();
    final run = container.read(actionRunnerProvider).runAndRefresh<String>(
      key: 'fetch',
      repo: repo,
      scopes: const {RefreshScope.status, RefreshScope.graph},
      action: () async {
        // A streamed network op registers a cancel hook, which is what the
        // blocking indicator and the toast both surface.
        opId = ops.start(
          OpKind.fetch,
          'Fetching origin',
          repo: repo,
          onCancel: () {},
        );
        ops.updateProgress(opId, 0.45, 'remote: counting objects');
        await gitDone.future;
        // What GitActionsService does now instead of reporting success.
        ops.updateProgress(opId, null, 'Updating views…');
        return opId;
      },
      operationId: (id) => id,
    );

    // 1. Fetch running: progress toast plus the blocking indicator.
    await tester.pump(const Duration(milliseconds: 200));
    await shoot(tester, key, 'fetch_01_running.png');

    // 2. git has exited; the graph is still reloading and busy holds.
    gitDone.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(graph.loads, 2);
    expect(container.read(busyProvider).isBusy, isTrue);
    await shoot(tester, key, 'fetch_02_git_done_view_reloading.png');

    // 3. The views caught up: indicator gone, success toast.
    graph.release();
    await pumpUntil(tester, () => !container.read(busyProvider).isBusy);
    await tester.pump(const Duration(milliseconds: 600));
    expect((await run).status, ActionRunStatus.succeeded);
    await shoot(tester, key, 'fetch_03_refreshed.png');
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('renders the refresh-failure state', (tester) async {
    final previous = goldenFileComparator;
    goldenFileComparator = _screenshots;
    addTearDown(() => goldenFileComparator = previous);
    final key = GlobalKey();
    final graph = _GatedGraph(fail: true);
    final container = await start(tester, graph, key);

    final ops = container.read(operationsProvider.notifier);
    final run = container.read(actionRunnerProvider).runAndRefresh<String>(
      key: 'fetch',
      repo: repo,
      scopes: const {RefreshScope.status, RefreshScope.graph},
      action: () async =>
          ops.start(OpKind.fetch, 'Fetching origin', repo: repo),
      operationId: (id) => id,
    );
    await tester.pump(const Duration(milliseconds: 200));
    graph.release();
    await pumpUntil(tester, () => !container.read(busyProvider).isBusy);
    await tester.pump(const Duration(milliseconds: 600));

    expect((await run).status, ActionRunStatus.refreshFailed);
    expect(find.text(refreshFailureMessage), findsOneWidget);
    await shoot(tester, key, 'fetch_04_refresh_error.png');
    await tester.binding.setSurfaceSize(null);
  });
}
