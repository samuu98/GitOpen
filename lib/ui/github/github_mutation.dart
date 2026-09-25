import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/git/action_runner.dart';

String githubMutationKey(RepoLocation repo, String key) =>
    '${repo.id.value}/github/$key';

bool githubMutationPending(WidgetRef ref, RepoLocation repo, String key) =>
    ref.watch(busyProvider).isRunning(githubMutationKey(repo, key));

Future<ActionRun<T>> runGitHubMutation<T>(
  WidgetRef ref, {
  required RepoLocation repo,
  required String key,
  required RepoSlug slug,
  required String token,
  required Future<T> Function() action,
  int? pullRequest,
  int? Function(T value)? createdNumber,
  bool reviewData = false,
  int? runId,
  String? branch,
  Set<RefreshScope> scopes = const {},
  String? successMessage,
}) => ref
    .read(actionRunnerProvider)
    .runAndRefresh<T>(
      key: 'github/$key',
      repo: repo,
      scopes: {
        ...scopes,
        ..._gitHubScopes(
          pullRequest: pullRequest != null || createdNumber != null,
          reviewData: reviewData,
          workflowRun: runId != null,
        ),
      },
      successMessage: successMessage,
      action: action,
      gitHubTarget: (value) => GitHubRefreshTarget(
        slug: slug,
        token: token,
        pullRequest: pullRequest ?? createdNumber?.call(value),
        runId: runId,
        branch: branch,
      ),
    );

/// The GitHub views a mutation reloads: a workflow run's list and jobs, or a
/// pull request's list, detail and review data, or — with nothing else named —
/// just the pull-request list.
Set<RefreshScope> _gitHubScopes({
  required bool pullRequest,
  required bool reviewData,
  required bool workflowRun,
}) {
  if (workflowRun) {
    return const {RefreshScope.workflowRuns, RefreshScope.workflowJobs};
  }
  if (!pullRequest) return const {RefreshScope.pullRequestList};
  return {
    RefreshScope.pullRequestList,
    RefreshScope.pullRequestDetail,
    if (reviewData) RefreshScope.pullRequestReviewData,
  };
}
