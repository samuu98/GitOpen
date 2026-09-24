import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/github/github_api.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/ui/common/app_animated_row.dart';
import 'package:gitopen/ui/github/github_panel.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/operations.dart';
import '../../_helpers/screenshot.dart';

final class _FakeApi implements GitHubApi {
  _FakeApi({
    this.error,
    this.detailDraft = true,
    this.detailMergeStateStatus = 'clean',
    this.runStatus = 'completed',
    this.updateError,
    this.emptyPr = false,
  });
  final GitHubApiException? error;
  final bool detailDraft;
  final String detailMergeStateStatus;
  final String runStatus;
  final Error? updateError;
  final bool emptyPr;
  CreatePullRequestRequest? createdRequest;
  UpdatePullRequestRequest? updatedRequest;
  MergePullRequestRequest? mergedRequest;
  SubmitReviewRequest? submittedReview;
  String? createdIssueComment;
  String? replyBody;
  bool markedReady = false;
  List<WorkflowJob> jobs = const [];
  String jobLog = '';
  int? rerunRunId;
  int? rerunFailedRunId;
  int? cancelRunId;
  int? loggedJobId;
  Completer<void>? detailGate;
  int detailCalls = 0;
  int updateCalls = 0;
  int readyCalls = 0;
  Completer<void>? initialPrGate;
  Completer<void>? runsGate;
  int runsCalls = 0;

  @override
  Future<List<PullRequestInfo>> listPullRequests(
    RepoSlug slug, {
    required String token,
  }) async {
    await initialPrGate?.future;
    final err = error;
    if (err != null) throw err;
    if (emptyPr) return [];
    return [
      PullRequestInfo(
        number: 12,
        title: 'Improve the widget',
        author: 'ada',
        isDraft: detailDraft && !markedReady,
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
    runsCalls++;
    if (runsCalls > 1) await runsGate?.future;
    return [
      WorkflowRunInfo(
        id: 9,
        name: 'CI GitOpen',
        headBranch: branch ?? 'main',
        status: runStatus,
        conclusion: runStatus == 'completed' ? 'success' : null,
        htmlUrl: 'https://github.com/o/r/actions/runs/9',
        createdAt: DateTime.utc(2026, 6, 11, 10),
        updatedAt: DateTime.utc(2026, 6, 11, 10, 3, 30),
      ),
    ];
  }

  @override
  Future<List<WorkflowJob>> listWorkflowJobs(
    RepoSlug slug,
    int runId, {
    required String token,
  }) async => jobs;

  @override
  Future<void> rerunWorkflowRun(
    RepoSlug slug,
    int runId, {
    required String token,
  }) async => rerunRunId = runId;

  @override
  Future<void> rerunFailedJobs(
    RepoSlug slug,
    int runId, {
    required String token,
  }) async => rerunFailedRunId = runId;

  @override
  Future<void> cancelWorkflowRun(
    RepoSlug slug,
    int runId, {
    required String token,
  }) async => cancelRunId = runId;

  @override
  Future<String> jobLogs(
    RepoSlug slug,
    int jobId, {
    required String token,
  }) async {
    loggedJobId = jobId;
    return jobLog;
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
  }) async {
    detailCalls++;
    if (detailCalls > 1) await detailGate?.future;
    return PullRequestDetail(
      number: number,
      nodeId: 'PR_kwDOExample',
      title: 'Improve the widget',
      body: 'Detailed body',
      author: 'ada',
      state: updatedRequest?.state ?? 'open',
      isDraft: detailDraft && !markedReady,
      mergeable: true,
      mergeStateStatus: detailMergeStateStatus,
      baseRef: 'main',
      headRef: 'feat/widget',
      headSha: 'a' * 40,
      htmlUrl: 'https://github.com/o/r/pull/$number',
      createdAt: DateTime.utc(2026, 6, 10),
      updatedAt: DateTime.utc(2026, 6, 11),
    );
  }

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
    final error = updateError;
    if (error != null) throw error;
    updateCalls++;
    updatedRequest = request;
    return getPullRequest(slug, number, token: token);
  }

  @override
  Future<PullRequestDetail> markPullRequestReadyForReview(
    RepoSlug slug,
    int number, {
    required String token,
  }) async {
    readyCalls++;
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
  AppPalette? palette,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitHubApiProvider.overrideWithValue(api),
        operationsProvider.overrideWith(
          (ref) => OperationsNotifier(InMemoryActivityLog()),
        ),
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
      child: RepaintBoundary(
        key: const Key('shot'),
        child: MaterialApp(
          theme: ThemeData(extensions: [palette ?? AppPalette.dark()]),
          home: Scaffold(
            backgroundColor: (palette ?? AppPalette.dark()).bg0,
            body: ColoredBox(
              color: (palette ?? AppPalette.dark()).bg0,
              child: GitHubPanel(key: ValueKey(api), repo: repo),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
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

  testWidgets('Actions: re-run all jobs calls the API', (tester) async {
    final api = _FakeApi();
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Re-run all jobs'));
    await tester.pumpAndSettle();

    expect(api.rerunRunId, 9);
  });

  testWidgets('Actions: opening a run shows its jobs and steps', (
    tester,
  ) async {
    final api = _FakeApi()
      ..jobs = const [
        WorkflowJob(
          id: 5,
          name: 'build',
          status: 'completed',
          conclusion: 'failure',
          htmlUrl: 'https://github.com/o/r/actions/runs/9/job/5',
          steps: [
            WorkflowStep(
              name: 'checkout',
              status: 'completed',
              conclusion: 'success',
              number: 1,
            ),
            WorkflowStep(
              name: 'unit tests',
              status: 'completed',
              conclusion: 'failure',
              number: 2,
            ),
          ],
        ),
      ];
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CI GitOpen'));
    await tester.pumpAndSettle();

    expect(find.text('build'), findsOneWidget);
    expect(find.text('checkout'), findsOneWidget);
    expect(find.text('unit tests'), findsOneWidget);
  });

  testWidgets('Actions: viewing a job log fetches and shows it', (
    tester,
  ) async {
    final api = _FakeApi()
      ..jobLog = 'compiling sources...\nBUILD DONE'
      ..jobs = const [
        WorkflowJob(
          id: 5,
          name: 'build',
          status: 'completed',
          conclusion: 'success',
          htmlUrl: 'https://github.com/o/r/actions/runs/9/job/5',
          steps: [],
        ),
      ];
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CI GitOpen'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('View job log'));
    await tester.pumpAndSettle();

    expect(api.loggedJobId, 5);
    expect(find.textContaining('compiling sources...'), findsOneWidget);
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
    // A draft PR can't be merged (mirrors GitHub) — use a ready one here.
    final api = _FakeApi(detailDraft: false);
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

  testWidgets('Merge is disabled while branch protection blocks it', (
    tester,
  ) async {
    final api = _FakeApi(detailDraft: false, detailMergeStateStatus: 'blocked');
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Improve the widget'));
    await tester.pumpAndSettle();

    // The disabled Merge button opens no dialog and triggers no API call.
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm merge'), findsNothing);
    expect(api.mergedRequest, isNull);
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
    expect(find.text('Close pull request?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.updatedRequest, isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();

    expect(api.updatedRequest?.state, 'closed');
  });

  testWidgets('PR mutation remains pending until refreshed detail resolves', (
    tester,
  ) async {
    final api = _FakeApi()..detailGate = Completer<void>();
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Improve the widget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ready'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Working…'), findsOneWidget);
    await tester.tap(find.text('Working…'));
    expect(api.markedReady, isTrue);
    expect(api.readyCalls, 1);
    expect(api.detailCalls, 2);
    api.detailGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsNothing);
  });

  testWidgets('PR mutation error stays inline without a snackbar', (
    tester,
  ) async {
    final api = _FakeApi(updateError: StateError('Could not update'));
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Improve the widget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not update'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Cancel workflow run confirmation leaves API untouched', (
    tester,
  ) async {
    final api = _FakeApi(runStatus: 'in_progress');
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Actions'));
    for (
      var i = 0;
      i < 10 && find.byTooltip('Cancel run').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byTooltip('Cancel run'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel run'));
    await tester.pump();
    expect(find.text('Cancel workflow run?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(api.cancelRunId, isNull);
  });

  testWidgets('Rerun stays pending through runs reload and ignores repeat', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    api.runsGate = Completer<void>();
    final before = api.runsCalls;
    await tester.tap(find.byTooltip('Re-run all jobs'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip('Re-run all jobs'));
    expect(api.rerunRunId, 9);
    expect(api.runsCalls, before + 1);
    api.runsGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('queues a line comment and submits review', (tester) async {
    final api = _FakeApi();
    await _pump(tester, repo: repo, api: api, profile: profile);
    await tester.tap(find.text('Improve the widget'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Comment on line 2').first);
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

  for (final (name, palette) in [
    ('dark', AppPalette.dark()),
    ('light', AppPalette.light()),
  ]) {
    testWidgets('GitHub visual states $name', (tester) async {
      final previous = goldenFileComparator;
      final shots = PipelineScreenshotComparator('ux-l8-github');
      goldenFileComparator = shots;
      addTearDown(() => goldenFileComparator = previous);

      Future<void> capture(String state) async {
        final file = 'github_${state}_$name.png';
        await expectLater(
          find.byKey(const Key('shot')),
          matchesGoldenFile(file),
        );
        expect(shots.fileFor(file).existsSync(), isTrue);
      }

      final api = _FakeApi();
      await _pump(
        tester,
        repo: repo,
        api: api,
        profile: profile,
        palette: palette,
      );
      await capture('pr_list');
      expect(
        tester
            .widget<AppAnimatedRow>(find.byType(AppAnimatedRow).first)
            .selected,
        isFalse,
      );
      await tester.tap(find.text('Improve the widget'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppAnimatedRow>(find.byType(AppAnimatedRow).first)
            .selected,
        isTrue,
      );
      api.detailGate = Completer<void>();
      await tester.tap(find.text('Ready'));
      await tester.pump(const Duration(milliseconds: 300));
      await capture('pr_pending');
      api.detailGate!.complete();
      await tester.pumpAndSettle();
      await capture('pr_reloaded');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await capture('close_confirmation');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(find.text('Actions')));
      await tester.pump(const Duration(milliseconds: 250));
      await capture('tabs_hover');
      await mouse.removePointer();
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (Focus.of(tester.element(find.text('Actions'))).hasFocus) break;
      }
      expect(Focus.of(tester.element(find.text('Actions'))).hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 250));
      await capture('tabs_focus');
      await tester.tap(find.text('Actions'));
      await tester.pumpAndSettle();
      api.runsGate = Completer<void>();
      await tester.tap(find.byTooltip('Re-run all jobs'));
      await tester.pump(const Duration(milliseconds: 300));
      await capture('actions_pending');
      api.runsGate!.complete();
      await tester.pumpAndSettle();

      final running = _FakeApi(runStatus: 'in_progress');
      await _pump(
        tester,
        repo: repo,
        api: running,
        profile: profile,
        palette: palette,
      );
      await tester.tap(find.text('Actions'));
      for (
        var i = 0;
        i < 10 && find.byTooltip('Cancel run').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byTooltip('Cancel run'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel workflow run?'), findsOneWidget);
      await capture('cancel_confirmation');
      await tester.tap(find.text('Cancel'));

      final loading = _FakeApi()..initialPrGate = Completer<void>();
      await _pump(
        tester,
        repo: repo,
        api: loading,
        profile: profile,
        palette: palette,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await capture('loading');
      loading.initialPrGate!.complete();

      await _pump(tester, repo: repo, api: _FakeApi(), palette: palette);
      await capture('sign_in');
      await _pump(
        tester,
        repo: repo,
        api: _FakeApi(emptyPr: true),
        profile: profile,
        palette: palette,
      );
      await capture('empty');
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
        palette: palette,
      );
      await capture('error');
    });
  }
}
