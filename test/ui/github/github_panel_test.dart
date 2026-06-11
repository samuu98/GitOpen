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
