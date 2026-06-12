import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/github/github_api.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/ui/github/github_panel.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final class _FakeApi implements GitHubApi {
  _FakeApi({this.error});
  final GitHubApiException? error;

  @override
  Future<List<PullRequestInfo>> listPullRequests(
    RepoSlug slug, {
    required String token,
  }) async {
    final err = error;
    if (err != null) throw err;
    return [
      PullRequestInfo(
        number: 12,
        title: 'Improve the widget',
        author: 'ada',
        isDraft: true,
        headRef: 'feat/widget',
        headSha: 'a' * 40,
        htmlUrl: 'https://github.com/o/r/pull/12',
        updatedAt: DateTime.utc(2026, 6, 11),
      ),
    ];
  }

  @override
  Future<List<WorkflowRunInfo>> listWorkflowRuns(
    RepoSlug slug, {
    required String token,
    String? branch,
  }) async {
    return [
      WorkflowRunInfo(
        id: 9,
        name: 'CI GitOpen',
        headBranch: branch ?? 'main',
        status: 'completed',
        conclusion: 'success',
        htmlUrl: 'https://github.com/o/r/actions/runs/9',
        createdAt: DateTime.utc(2026, 6, 11, 10),
        updatedAt: DateTime.utc(2026, 6, 11, 10, 3, 30),
      ),
    ];
  }

  @override
  Future<CheckSummary> prChecks(
    RepoSlug slug,
    String headSha, {
    required String token,
  }) async => const CheckSummary(total: 2, succeeded: 2, failed: 0, pending: 0);

  @override
  Future<PullRequestDetail> getPullRequest(
    RepoSlug slug,
    int number, {
    required String token,
  }) async => PullRequestDetail(
    number: number,
    nodeId: 'PR_kwDOExample',
    title: 'Improve the widget',
    body: 'Detailed body',
    author: 'ada',
    state: 'open',
    isDraft: true,
    mergeable: true,
    mergeStateStatus: 'clean',
    baseRef: 'main',
    headRef: 'feat/widget',
    headSha: 'a' * 40,
    htmlUrl: 'https://github.com/o/r/pull/$number',
    createdAt: DateTime.utc(2026, 6, 10),
    updatedAt: DateTime.utc(2026, 6, 11),
  );

  @override
  Future<List<PullRequestFile>> listPullRequestFiles(
    RepoSlug slug,
    int number, {
    required String token,
  }) async => const [];

  @override
  Future<List<PullRequestReview>> listPullRequestReviews(
    RepoSlug slug,
    int number, {
    required String token,
  }) async => const [];

  @override
  Future<List<PullRequestComment>> listPullRequestReviewComments(
    RepoSlug slug,
    int number, {
    required String token,
  }) async => const [];

  @override
  Future<List<IssueCommentInfo>> listPullRequestIssueComments(
    RepoSlug slug,
    int number, {
    required String token,
  }) async => const [];

  @override
  Future<PullRequestDetail> createPullRequest(
    RepoSlug slug,
    CreatePullRequestRequest request, {
    required String token,
  }) async => getPullRequest(slug, 13, token: token);

  @override
  Future<PullRequestDetail> updatePullRequest(
    RepoSlug slug,
    int number,
    UpdatePullRequestRequest request, {
    required String token,
  }) async => getPullRequest(slug, number, token: token);

  @override
  Future<PullRequestDetail> markPullRequestReadyForReview(
    RepoSlug slug,
    int number, {
    required String token,
  }) async => getPullRequest(slug, number, token: token);

  @override
  Future<void> mergePullRequest(
    RepoSlug slug,
    int number,
    MergePullRequestRequest request, {
    required String token,
  }) async {}

  @override
  Future<IssueCommentInfo> createIssueComment(
    RepoSlug slug,
    int number,
    String body, {
    required String token,
  }) async => IssueCommentInfo(
    id: 1,
    user: 'ada',
    body: body,
    createdAt: DateTime.utc(2026, 6, 11),
    updatedAt: DateTime.utc(2026, 6, 11),
    htmlUrl: 'https://github.com/o/r/pull/$number#issuecomment-1',
  );

  @override
  Future<PullRequestReview> createReview(
    RepoSlug slug,
    int number,
    SubmitReviewRequest request, {
    required String token,
  }) async => PullRequestReview(
    id: 1,
    user: 'ada',
    state: request.event,
    body: request.body,
    submittedAt: DateTime.utc(2026, 6, 11),
    htmlUrl: 'https://github.com/o/r/pull/$number#pullrequestreview-1',
  );

  @override
  Future<PullRequestComment> createReviewCommentReply(
    RepoSlug slug,
    int number,
    int commentId,
    String body, {
    required String token,
  }) async => PullRequestComment(
    id: 2,
    user: 'ada',
    body: body,
    path: 'lib/widget.dart',
    side: 'RIGHT',
    line: 2,
    position: null,
    inReplyToId: commentId,
    createdAt: DateTime.utc(2026, 6, 11),
    updatedAt: DateTime.utc(2026, 6, 11),
    htmlUrl: 'https://github.com/o/r/pull/$number#discussion_r2',
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required RepoLocation repo,
  required GitHubApi api,
  AuthProfile? profile,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitHubApiProvider.overrideWithValue(api),
        githubSlugProvider.overrideWith(
          (ref, repo) async => (owner: 'o', repo: 'r'),
        ),
        repoActiveProfileProvider.overrideWith((ref, repo) async => profile),
        repoStatusProvider.overrideWith(
          (ref, repo) async => const RepoStatus(
            isDetached: false,
            isBare: false,
            entries: [],
            currentBranch: 'main',
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 500,
            child: GitHubPanel(repo: repo),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
  const profile = AuthProfile(
    id: 'p1',
    host: 'github.com',
    username: 'ada',
    spec: AuthGitHubOauth('tok'),
  );

  testWidgets('no usable token shows the sign-in CTA', (tester) async {
    await _pump(tester, repo: repo, api: _FakeApi());
    expect(find.text('Sign in with GitHub'), findsOneWidget);
  });

  testWidgets('lists open pull requests with draft badge and checks', (
    tester,
  ) async {
    await _pump(tester, repo: repo, api: _FakeApi(), profile: profile);
    expect(find.text('#12'), findsOneWidget);
    expect(find.text('Improve the widget'), findsOneWidget);
    expect(find.text('DRAFT'), findsOneWidget);
    expect(find.text('ada'), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('Actions tab lists runs for the current branch', (tester) async {
    await _pump(tester, repo: repo, api: _FakeApi(), profile: profile);
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('CI GitOpen'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.textContaining('3m 30s'), findsOneWidget);
  });

  testWidgets('a network error renders inline with a Retry button', (
    tester,
  ) async {
    await _pump(
      tester,
      repo: repo,
      api: _FakeApi(
        error: const GitHubApiException(
          GitHubApiErrorKind.network,
          'GitHub API returned 500.',
        ),
      ),
      profile: profile,
    );
    expect(find.textContaining('GitHub API returned 500'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
