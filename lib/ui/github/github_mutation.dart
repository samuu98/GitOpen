import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/github/github_providers.dart';

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
      scopes: scopes,
      successMessage: successMessage,
      action: () async {
        final result = await action();
        final listKey = (slug: slug, token: token);
        final number = pullRequest ?? createdNumber?.call(result);
        if (number != null) {
          final detailKey = (slug: slug, token: token, number: number);
          ref
            ..invalidate(githubPullRequestsProvider(listKey))
            ..invalidate(githubPullRequestDetailProvider(detailKey));
          await Future.wait<dynamic>([
            ref.read(githubPullRequestsProvider(listKey).future),
            ref.read(githubPullRequestDetailProvider(detailKey).future),
          ]);
          if (reviewData) {
            ref
              ..invalidate(githubPullRequestReviewsProvider(detailKey))
              ..invalidate(githubPullRequestCommentsProvider(detailKey))
              ..invalidate(githubIssueCommentsProvider(detailKey));
            await Future.wait<dynamic>([
              ref.read(githubPullRequestReviewsProvider(detailKey).future),
              ref.read(githubPullRequestCommentsProvider(detailKey).future),
              ref.read(githubIssueCommentsProvider(detailKey).future),
            ]);
          }
        } else if (runId != null) {
          final runsKey = (slug: slug, token: token, branch: branch);
          final jobsKey = (slug: slug, token: token, runId: runId);
          ref
            ..invalidate(githubWorkflowRunsProvider(runsKey))
            ..invalidate(githubWorkflowJobsProvider(jobsKey));
          await Future.wait<dynamic>([
            ref.read(githubWorkflowRunsProvider(runsKey).future),
            ref.read(githubWorkflowJobsProvider(jobsKey).future),
          ]);
        } else {
          ref.invalidate(githubPullRequestsProvider(listKey));
          await ref.read(githubPullRequestsProvider(listKey).future);
        }
        return result;
      },
    );
