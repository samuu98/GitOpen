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
  CreatePullRequestRequest? createdRequest;
  UpdatePullRequestRequest? updatedRequest;
  MergePullRequestRequest? mergedRequest;
  SubmitReviewRequest? submittedReview;
  String? createdIssueComment;
  String? replyBody;
  bool markedReady = false;

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
  }) async => const [
    PullRequestFile(
      filename: 'lib/widget.dart',
      status: 'modified',
      additions: 2,
      deletions: 1,
      changes: 3,
      patch: '@@ -1 +1,2 @@\n-old\n+new\n+line',
    ),
  ];

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
  }) async {
    createdRequest = request;
    return getPullRequest(slug, 13, token: token);
  }

  @override
  Future<PullRequestDetail> updatePullRequest(
    RepoSlug slug,
    int number,
    UpdatePullRequestRequest request, {
    required String token,
  }) async {
    updatedRequest = request;
    return getPullRequest(slug, number, token: token);
  }

  @override
  Future<PullRequestDetail> markPullRequestReadyForReview(
    RepoSlug slug,
    int number, {
    required String token,
  }) async {
    markedReady = true;
    return getPullRequest(slug, number, token: token);
  }

  @override
  Future<void> mergePullRequest(
    RepoSlug slug,
    int number,
    MergePullRequestRequest request, {
    required String token,
  }) async {
    mergedRequest = request;
  }

  @override
  Future<IssueCommentInfo> createIssueComment(
    RepoSlug slug,
    int number,
    String body, {
    required String token,
  }) async {
    createdIssueComment = body;
    return IssueCommentInfo(
      id: 1,
      user: 'ada',
      body: body,
      createdAt: DateTime.utc(2026, 6, 11),
      updatedAt: DateTime.utc(2026, 6, 11),
      htmlUrl: 'https://github.com/o/r/pull/$number#issuecomment-1',
    );
  }

  @override
  Future<PullRequestReview> createReview(
    RepoSlug slug,
    int number,
    SubmitReviewRequest request, {
    required String token,
  }) async {
    submittedReview = request;
    return PullRequestReview(
      id: 1,
      user: 'ada',
      state: request.event,
      body: request.body,
      submittedAt: DateTime.utc(2026, 6, 11),
      htmlUrl: 'https://github.com/o/r/pull/$number#pullrequestreview-1',
    );
  }

  @override
  Future<PullRequestComment> createReviewCommentReply(
    RepoSlug slug,
    int number,
    int commentId,
    String body, {
    required String token,
  }) async {
    replyBody = body;
    return PullRequestComment(
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
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
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

  testWidgets('selecting a PR shows detail and changed files', (tester) async {
    await _pump(tester, repo: repo, api: _FakeApi(), profile: profile);

    await tester.tap(find.text('Improve the widget'));
    await tester.pumpAndSettle();

    expect(find.text('Detailed body'), findsOneWidget);
    expect(find.text('main <- feat/widget'), findsOneWidget);
    expect(find.text('lib/widget.dart'), findsOneWidget);
    expect(find.textContaining('+new'), findsOneWidget);
  });

  testWidgets('Create PR dialog calls createPullRequest', (tester) async {
    final api = _FakeApi();
    await _pump(tester, repo: repo, api: api, profile: profile);

    await tester.tap(find.text('Create PR'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('create-pr-title')), 'New PR');
    await tester.enterText(find.byKey(const Key('create-pr-body')), 'Body');
    await tester.enterText(find.byKey(const Key('create-pr-base')), 'main');
    await tester.enterText(
      find.byKey(const Key('create-pr-head')),
      'feat/widget',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(api.createdRequest?.title, 'New PR');
    expect(api.createdRequest?.base, 'main');
  });

  testWidgets('Merge PR dialog calls mergePullRequest', (tester) async {
    final api = _FakeApi();
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Improve the widget'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Squash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm merge'));
    await tester.pumpAndSettle();

    expect(api.mergedRequest?.method, PullRequestMergeMethod.squash);
  });

  testWidgets('Ready button marks a draft PR ready for review', (tester) async {
    final api = _FakeApi();
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Improve the widget'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ready'));
    await tester.pumpAndSettle();

    expect(api.markedReady, isTrue);
  });

  testWidgets('Close button updates PR state to closed', (tester) async {
    final api = _FakeApi();
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Improve the widget'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(api.updatedRequest?.state, 'closed');
  });

  testWidgets('queues a line comment and submits review', (tester) async {
    final api = _FakeApi();
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Improve the widget'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Comment on line 2'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('review-line-comment-body')),
      'Please adjust',
    );
    await tester.tap(find.text('Queue comment'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('review-summary-body')),
      'Looks close',
    );
    await tester.tap(find.text('Comment'));
    await tester.pumpAndSettle();

    expect(api.submittedReview?.body, 'Looks close');
    expect(api.submittedReview?.comments.single.body, 'Please adjust');
    expect(api.submittedReview?.comments.single.path, 'lib/widget.dart');
  });

  testWidgets('adds a conversation comment', (tester) async {
    final api = _FakeApi();
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Improve the widget'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('issue-comment-body')),
      'Top level',
    );
    await tester.ensureVisible(find.text('Add comment'));
    await tester.tap(find.text('Add comment'));
    await tester.pumpAndSettle();

    expect(api.createdIssueComment, 'Top level');
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
