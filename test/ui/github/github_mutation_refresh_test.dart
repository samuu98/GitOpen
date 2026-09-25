import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/github/github_mutation.dart';
import 'package:gitopen/ui/github/github_providers.dart';

import '../../_helpers/operations.dart';

const _repo = RepoLocation(RepoId('repo'), 'C:/repo', 'repo');
const _slug = (owner: 'o', repo: 'r');
const _token = 't';
const _number = 7;
const _runId = 3;
const _branch = 'main';

/// The GitHub views a mutation can reload.
enum _View { list, detail, reviews, issueComments, runs, jobs }

final _detail = PullRequestDetail(
  number: _number,
  nodeId: 'PR_7',
  title: 'Title',
  body: '',
  author: 'me',
  state: 'open',
  isDraft: false,
  mergeable: true,
  mergeStateStatus: 'clean',
  baseRef: 'main',
  headRef: 'feature',
  headSha: 'abc',
  htmlUrl: 'https://github.com/o/r/pull/7',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Object? _value(_View view) => view == _View.detail ? _detail : const <Never>[];

ProviderListenable<Object?> _provider(_View view) {
  const pr = (slug: _slug, token: _token, number: _number);
  return switch (view) {
    _View.list => githubPullRequestsProvider((slug: _slug, token: _token)),
    _View.detail => githubPullRequestDetailProvider(pr),
    _View.reviews => githubPullRequestReviewsProvider(pr),
    _View.issueComments => githubIssueCommentsProvider(pr),
    _View.runs => githubWorkflowRunsProvider((
      slug: _slug,
      token: _token,
      branch: _branch,
    )),
    _View.jobs => githubWorkflowJobsProvider((
      slug: _slug,
      token: _token,
      runId: _runId,
    )),
  };
}

/// One mutation group: what it runs, the view its screen has open and a view
/// it reloads that nobody has open.
typedef _Group = ({
  String name,
  String key,
  _View onScreen,
  _View offScreen,
  Future<ActionRun<int>> Function(WidgetRef ref) run,
});

final List<_Group> _groups = [
  (
    name: 'create pull request',
    key: 'pr/create',
    onScreen: _View.list,
    offScreen: _View.detail,
    run: (ref) => _mutate(ref, 'pr/create', createdNumber: (n) => n),
  ),
  (
    name: 'pull-request action',
    key: 'pr/$_number',
    onScreen: _View.detail,
    offScreen: _View.list,
    run: (ref) => _mutate(ref, 'pr/$_number', pullRequest: _number),
  ),
  (
    name: 'review or comment',
    key: 'pr/$_number/review',
    onScreen: _View.reviews,
    offScreen: _View.issueComments,
    run: (ref) => _mutate(
      ref,
      'pr/$_number/review',
      pullRequest: _number,
      reviewData: true,
    ),
  ),
  (
    name: 'workflow-run action',
    key: 'run/$_runId',
    onScreen: _View.jobs,
    offScreen: _View.runs,
    run: (ref) => _mutate(ref, 'run/$_runId', runId: _runId, branch: _branch),
  ),
];

Future<ActionRun<int>> _mutate(
  WidgetRef ref,
  String key, {
  int? pullRequest,
  int? Function(int value)? createdNumber,
  bool reviewData = false,
  int? runId,
  String? branch,
}) => runGitHubMutation<int>(
  ref,
  repo: _repo,
  key: key,
  slug: _slug,
  token: _token,
  pullRequest: pullRequest,
  createdNumber: createdNumber,
  reviewData: reviewData,
  runId: runId,
  branch: branch,
  action: () async => _number,
);

void main() {
  for (final group in _groups) {
    testWidgets('a failing reload after a ${group.name} is a refresh '
        'failure', (tester) async {
      final api = _Api()
        ..reload[group.onScreen] = () =>
            Future<Object?>.error(StateError('GitHub API down'));
      final host = await _pumpHost(tester, api, {group.onScreen});

      final run = await group.run(host.ref);
      await tester.pump();

      expect(api.loads[group.onScreen], 2, reason: 'the view reloaded');
      expect(run.status, ActionRunStatus.refreshFailed);
      final ops = host.container.read(operationsProvider);
      expect(ops.map((o) => o.errorMessage), [refreshFailureMessage]);
      expect(ops.single.onRetry, isNotNull);
    });

    testWidgets('a ${group.name} stays pending until its view reloads', (
      tester,
    ) async {
      final reload = Completer<Object?>();
      final api = _Api()..reload[group.onScreen] = () => reload.future;
      final host = await _pumpHost(tester, api, {group.onScreen});
      bool pending() => host.container
          .read(busyProvider)
          .isRunning(githubMutationKey(_repo, group.key));

      ActionRun<int>? run;
      unawaited(group.run(host.ref).then((r) => run = r));
      await tester.pump();
      await tester.pump();
      expect(api.loads[group.onScreen], 2);
      expect(run, isNull);
      expect(pending(), isTrue);

      reload.complete(_value(group.onScreen));
      await tester.pump();
      await tester.pump();
      expect(run?.status, ActionRunStatus.succeeded);
      expect(pending(), isFalse);
    });

    testWidgets('a ${group.name} does not await a view nobody has open', (
      tester,
    ) async {
      final api = _Api()
        ..reload[group.offScreen] = () => Completer<Object?>().future;
      final host = await _pumpHost(tester, api, {group.onScreen});

      final run = await group.run(host.ref);

      expect(run.status, ActionRunStatus.succeeded);
      expect(api.loads[group.offScreen], isNull);
    });
  }
}

/// Counts each view's loads; the first load returns data, later ones use
/// [reload] when the test set one.
final class _Api {
  final loads = <_View, int>{};
  final reload = <_View, Future<Object?> Function()>{};

  Future<T> load<T>(_View view) {
    final count = loads[view] = (loads[view] ?? 0) + 1;
    final next = reload[view];
    if (count > 1 && next != null) return next().then((v) => v as T);
    return Future.value(_value(view) as T);
  }

  List<Override> get overrides => [
    githubPullRequestsProvider.overrideWith((ref, k) => load(_View.list)),
    githubPullRequestDetailProvider.overrideWith(
      (ref, k) => load(_View.detail),
    ),
    githubPullRequestReviewsProvider.overrideWith(
      (ref, k) => load(_View.reviews),
    ),
    githubPullRequestCommentsProvider.overrideWith(
      (ref, k) async => const [],
    ),
    githubIssueCommentsProvider.overrideWith(
      (ref, k) => load(_View.issueComments),
    ),
    githubWorkflowRunsProvider.overrideWith((ref, k) => load(_View.runs)),
    githubWorkflowJobsProvider.overrideWith((ref, k) => load(_View.jobs)),
  ];
}

/// Pumps a host with [open] on screen and hands back its ref and container.
Future<({WidgetRef ref, ProviderContainer container})> _pumpHost(
  WidgetTester tester,
  _Api api,
  Set<_View> open,
) async {
  late WidgetRef captured;
  late BuildContext context;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        operationsProvider.overrideWith(
          (ref) => OperationsNotifier(InMemoryActivityLog()),
        ),
        ...api.overrides,
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (ctx, ref, _) {
            captured = ref;
            context = ctx;
            for (final view in open) {
              ref.watch(_provider(view));
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    ref: captured,
    container: ProviderScope.containerOf(context, listen: false),
  );
}
