# Phase 5 — S3 GitHub PRs + Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "GitHub" view (third segment in the view selector, shown only when `origin` is a github.com repo) with two tabs — open Pull Requests (with per-PR checkout and check status) and recent Actions workflow runs for the current branch — backed by a typed `GitHubApi` port with a REST implementation.

**Architecture:** Application owns the port (`GitHubApi`), immutable models (`PullRequestInfo`, `WorkflowRunInfo`, `CheckSummary`) and pure helpers (`githubSlugFromRemoteUrl`, `githubTokenOf`); infrastructure implements REST v3 with an injectable `http.Client` (same MockClient test pattern as the device flow). The token is reused from the existing auth-profile store via `repoActiveProfileProvider` — no `gh` CLI. PR checkout goes through the facade: a new `fetchRefspec` write op + `GitActionsService.checkoutPullRequest` (forced fetch of `pull/<n>/head` into `pr/<n>`, then checkout) with the standard progress + auth-retry.

**Tech Stack:** Dart/Flutter, riverpod, `package:http` (+ `http/testing` MockClient), system git CLI, url_launcher.

**Branch:** `feat/phase5-s3-github-prs-actions` from `main`. Version bump `0.1.19+20` → `0.1.20+21` in the final task.

**Process gotchas (repo conventions):**
- Flutter: `& "C:\Users\g.chirico\flutter\bin\flutter.bat"`; analyze MUST run from the repo dir; format ONLY touched files with `dart.bat format` (pre-tall-style codebase).
- gh CLI: `gh auth switch --hostname github.com --user zN3utr4l` before push; ALWAYS pass `--repo zN3utr4l/GitOpen` (the clone has an `upstream` remote pointing at the fork parent).
- Widgets watching `appSettingsProvider`/`repoActiveProfileProvider` need provider overrides in widget tests (default chains hit drift/DPAPI).
- Semantics asserts: `node.flagsCollection.isButton` / `.isSelected` (`Tristate`).

---

## File Structure

- Create: `lib/application/github/github_models.dart` (RepoSlug, PullRequestInfo, WorkflowRunInfo, CheckSummary)
- Create: `lib/application/github/github_api.dart` (port, GitHubApiException, `githubTokenOf`)
- Create: `lib/application/github/github_slug.dart` (pure `githubSlugFromRemoteUrl`)
- Test: `test/application/github/github_slug_test.dart`
- Create: `lib/infrastructure/github/github_rest_api.dart`
- Test: `test/infrastructure/github/github_rest_api_test.dart`
- Modify: `lib/application/git/git_write_operations.dart` (+`fetchRefspec`)
- Modify: `lib/infrastructure/git/git_cli_sync_writer.dart` (+impl)
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart:314-319` (+delegation)
- Test: `test/infrastructure/git/git_cli_write_operations_fetch_test.dart` (append)
- Modify: `lib/application/git/git_actions_service.dart` (+`checkoutPullRequest`)
- Test: `test/application/git/git_actions_service_github_test.dart` (new)
- Modify: `lib/ui/git/git_actions_controller.dart` (+`checkoutPullRequest`)
- Modify: `lib/application/providers.dart` (`remoteUrlReaderProvider`, `gitHubApiProvider`, `githubSlugProvider`)
- Modify: `lib/application/main_view_provider.dart` (`MainView.github`)
- Modify: `lib/ui/shell/view_selector.dart` (repo-aware + GitHub segment)
- Modify: `lib/main.dart` (`ViewSelector(repo:)` + github case in `_RepoBody`)
- Create: `lib/ui/github/github_panel.dart`
- Test: `test/ui/github/github_panel_test.dart`
- Modify: `pubspec.yaml` (version)

---

### Task 1: Branch setup

- [ ] **Step 1: Create the branch and commit this plan**

```powershell
git -C D:\repos\Personal\GitOpen checkout -b feat/phase5-s3-github-prs-actions main
git -C D:\repos\Personal\GitOpen add docs/superpowers/plans/2026-06-11-phase5-s3-github-prs-actions.md
git -C D:\repos\Personal\GitOpen commit -m "docs(phase5): S3 implementation plan - GitHub PRs + Actions"
```

---

### Task 2: Models, port and pure helpers

**Files:**
- Create: `lib/application/github/github_models.dart`
- Create: `lib/application/github/github_api.dart`
- Create: `lib/application/github/github_slug.dart`
- Test: `test/application/github/github_slug_test.dart`

- [ ] **Step 1: Write the failing pure tests** at `test/application/github/github_slug_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/github/github_api.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/github/github_slug.dart';

void main() {
  group('githubSlugFromRemoteUrl', () {
    test('parses https URLs with and without .git', () {
      expect(
        githubSlugFromRemoteUrl('https://github.com/zN3utr4l/GitOpen.git'),
        (owner: 'zN3utr4l', repo: 'GitOpen'),
      );
      expect(
        githubSlugFromRemoteUrl('https://github.com/a/b'),
        (owner: 'a', repo: 'b'),
      );
    });

    test('parses ssh URLs', () {
      expect(
        githubSlugFromRemoteUrl('git@github.com:a/b.git'),
        (owner: 'a', repo: 'b'),
      );
    });

    test('null for non-github hosts and malformed URLs', () {
      expect(githubSlugFromRemoteUrl('https://gitlab.com/a/b.git'), isNull);
      expect(githubSlugFromRemoteUrl('git@bitbucket.org:a/b.git'), isNull);
      expect(githubSlugFromRemoteUrl('https://github.com/onlyowner'), isNull);
      expect(githubSlugFromRemoteUrl('not a url'), isNull);
    });
  });

  group('githubTokenOf', () {
    test('extracts OAuth and PAT tokens', () {
      expect(githubTokenOf(const AuthGitHubOauth('tok1')), 'tok1');
      expect(
        githubTokenOf(const AuthHttpsPat(username: 'u', token: 'tok2')),
        'tok2',
      );
    });

    test('null for ssh/basic/system/null specs', () {
      expect(githubTokenOf(const AuthSsh(privateKeyPath: 'k')), isNull);
      expect(
        githubTokenOf(const AuthHttpsBasic(username: 'u', password: 'p')),
        isNull,
      );
      expect(githubTokenOf(const AuthSystemDefault()), isNull);
      expect(githubTokenOf(null), isNull);
    });
  });

  group('CheckSummary.state', () {
    test('aggregates to none/pending/failure/success', () {
      const none = CheckSummary(total: 0, succeeded: 0, failed: 0, pending: 0);
      const ok = CheckSummary(total: 2, succeeded: 2, failed: 0, pending: 0);
      const bad = CheckSummary(total: 3, succeeded: 1, failed: 1, pending: 1);
      const wip = CheckSummary(total: 2, succeeded: 1, failed: 0, pending: 1);
      expect(none.state, CheckState.none);
      expect(ok.state, CheckState.success);
      expect(bad.state, CheckState.failure); // failure wins over pending
      expect(wip.state, CheckState.pending);
    });
  });
}
```

- [ ] **Step 2: Run — fails to compile**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/github/github_slug_test.dart`
Expected: compile error (files missing).

- [ ] **Step 3: Implement** `lib/application/github/github_models.dart`:

```dart
import 'package:equatable/equatable.dart';

/// `owner/repo` pair identifying a GitHub repository.
typedef RepoSlug = ({String owner, String repo});

/// Aggregated state of a commit's check runs.
enum CheckState { none, pending, success, failure }

/// Counts of a commit's check runs by outcome. [state] folds them into the
/// single chip the PR list shows — any failure wins, then any pending.
final class CheckSummary extends Equatable {
  const CheckSummary({
    required this.total,
    required this.succeeded,
    required this.failed,
    required this.pending,
  });
  final int total;
  final int succeeded;
  final int failed;
  final int pending;

  CheckState get state => total == 0
      ? CheckState.none
      : failed > 0
          ? CheckState.failure
          : pending > 0
              ? CheckState.pending
              : CheckState.success;

  @override
  List<Object?> get props => [total, succeeded, failed, pending];
}

/// An open pull request, as listed by the GitHub REST API.
final class PullRequestInfo extends Equatable {
  const PullRequestInfo({
    required this.number,
    required this.title,
    required this.author,
    required this.isDraft,
    required this.headRef,
    required this.headSha,
    required this.htmlUrl,
    required this.updatedAt,
  });
  final int number;
  final String title;
  final String author;
  final bool isDraft;
  final String headRef;

  /// Sha of the PR's head commit — the ref [GitHubApi.prChecks] reports on.
  final String headSha;
  final String htmlUrl;
  final DateTime updatedAt;

  @override
  List<Object?> get props =>
      [number, title, author, isDraft, headRef, headSha, htmlUrl, updatedAt];
}

/// A GitHub Actions workflow run. [status] is the raw API value
/// (`queued`/`in_progress`/`completed`); [conclusion] is set only when
/// completed (`success`/`failure`/`cancelled`/…).
final class WorkflowRunInfo extends Equatable {
  const WorkflowRunInfo({
    required this.id,
    required this.name,
    required this.headBranch,
    required this.status,
    required this.htmlUrl,
    required this.createdAt,
    required this.updatedAt,
    this.conclusion,
  });
  final int id;
  final String name;
  final String headBranch;
  final String status;
  final String? conclusion;
  final String htmlUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCompleted => status == 'completed';
  Duration get duration => updatedAt.difference(createdAt);

  @override
  List<Object?> get props =>
      [id, name, headBranch, status, conclusion, htmlUrl, createdAt, updatedAt];
}
```

- [ ] **Step 4: Implement** `lib/application/github/github_api.dart`:

```dart
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/github/github_models.dart';

/// Why a GitHub API call failed, so the panel can render the right inline
/// state (sign-in CTA, rate-limit notice, retry, …).
enum GitHubApiErrorKind { auth, rateLimit, network, notFound }

/// Typed failure surfaced by [GitHubApi] implementations. `toString` is safe
/// to show to the user as-is.
final class GitHubApiException implements Exception {
  const GitHubApiException(this.kind, this.message);
  final GitHubApiErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Read-only GitHub data the panel needs. Implementations throw
/// [GitHubApiException] (never transport exceptions) on failure.
abstract interface class GitHubApi {
  /// Open pull requests of [slug], most recently updated first.
  Future<List<PullRequestInfo>> listPullRequests(
    RepoSlug slug, {
    required String token,
  });

  /// Recent Actions workflow runs of [slug]; [branch] filters to runs whose
  /// head is that branch.
  Future<List<WorkflowRunInfo>> listWorkflowRuns(
    RepoSlug slug, {
    required String token,
    String? branch,
  });

  /// Check-run summary for the commit [headSha] (a PR's head).
  Future<CheckSummary> prChecks(
    RepoSlug slug,
    String headSha, {
    required String token,
  });
}

/// The token usable for the GitHub REST API carried by [spec], or null when
/// the credential has no API-compatible token (ssh, basic, system default).
String? githubTokenOf(AuthSpec? spec) => switch (spec) {
      AuthGitHubOauth(:final accessToken) => accessToken,
      AuthHttpsPat(:final token) => token,
      _ => null,
    };
```

- [ ] **Step 5: Implement** `lib/application/github/github_slug.dart`:

```dart
import 'package:gitopen/application/github/github_models.dart';

final RegExp _https = RegExp(r'^https?://github\.com/([^/]+)/([^/]+?)(\.git)?/?$');
final RegExp _ssh = RegExp(r'^git@github\.com:([^/]+)/([^/]+?)(\.git)?$');

/// Extracts the `owner/repo` slug from a github.com remote URL (https or
/// ssh), or null for any other host or shape — non-GitHub origins simply
/// hide the GitHub panel.
RepoSlug? githubSlugFromRemoteUrl(String url) {
  final m = _https.firstMatch(url.trim()) ?? _ssh.firstMatch(url.trim());
  if (m == null) return null;
  return (owner: m.group(1)!, repo: m.group(2)!);
}
```

- [ ] **Step 6: Run — tests pass; analyze clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/github/github_slug_test.dart` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 7: Commit**

```powershell
git add lib/application/github test/application/github
git commit -m "feat(phase5): GitHubApi port, models and slug/token helpers"
```

---

### Task 3: REST implementation

**Files:**
- Create: `lib/infrastructure/github/github_rest_api.dart`
- Test: `test/infrastructure/github/github_rest_api_test.dart`

- [ ] **Step 1: Write the failing tests** at `test/infrastructure/github/github_rest_api_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/github/github_api.dart';
import 'package:gitopen/infrastructure/github/github_rest_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _slug = (owner: 'o', repo: 'r');

GitHubRestApi _api(MockClient client) => GitHubRestApi(client: client);

void main() {
  test('listPullRequests parses the fields the panel shows', () async {
    late Uri captured;
    final client = MockClient((request) async {
      captured = request.url;
      expect(request.headers['Authorization'], 'Bearer tok');
      return http.Response(
        jsonEncode([
          {
            'number': 7,
            'title': 'Add thing',
            'draft': true,
            'html_url': 'https://github.com/o/r/pull/7',
            'updated_at': '2026-06-11T10:00:00Z',
            'user': {'login': 'ada'},
            'head': {'ref': 'feat/x', 'sha': 'a' * 40},
          },
        ]),
        200,
      );
    });
    final prs = await _api(client).listPullRequests(_slug, token: 'tok');
    expect(captured.path, '/repos/o/r/pulls');
    expect(captured.queryParameters['state'], 'open');
    expect(prs, hasLength(1));
    final pr = prs.single;
    expect(pr.number, 7);
    expect(pr.title, 'Add thing');
    expect(pr.author, 'ada');
    expect(pr.isDraft, isTrue);
    expect(pr.headRef, 'feat/x');
    expect(pr.headSha, 'a' * 40);
    expect(pr.updatedAt.isUtc, isTrue);
  });

  test('listWorkflowRuns parses runs and passes the branch filter', () async {
    late Uri captured;
    final client = MockClient((request) async {
      captured = request.url;
      return http.Response(
        jsonEncode({
          'workflow_runs': [
            {
              'id': 99,
              'name': 'CI',
              'head_branch': 'main',
              'status': 'completed',
              'conclusion': 'success',
              'html_url': 'https://github.com/o/r/actions/runs/99',
              'created_at': '2026-06-11T10:00:00Z',
              'updated_at': '2026-06-11T10:03:30Z',
            },
          ],
        }),
        200,
      );
    });
    final runs = await _api(client)
        .listWorkflowRuns(_slug, token: 'tok', branch: 'main');
    expect(captured.path, '/repos/o/r/actions/runs');
    expect(captured.queryParameters['branch'], 'main');
    final run = runs.single;
    expect(run.id, 99);
    expect(run.isCompleted, isTrue);
    expect(run.conclusion, 'success');
    expect(run.duration, const Duration(minutes: 3, seconds: 30));
  });

  test('prChecks aggregates check runs into a summary', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/repos/o/r/commits/abc1234/check-runs');
      return http.Response(
        jsonEncode({
          'check_runs': [
            {'status': 'completed', 'conclusion': 'success'},
            {'status': 'completed', 'conclusion': 'neutral'},
            {'status': 'completed', 'conclusion': 'failure'},
            {'status': 'in_progress', 'conclusion': null},
          ],
        }),
        200,
      );
    });
    final summary = await _api(client).prChecks(_slug, 'abc1234', token: 't');
    expect(summary.total, 4);
    expect(summary.succeeded, 2); // success + neutral
    expect(summary.failed, 1);
    expect(summary.pending, 1);
  });

  test('maps HTTP failures to typed kinds', () async {
    Future<void> expectKind(
      http.Response response,
      GitHubApiErrorKind kind,
    ) async {
      final client = MockClient((_) async => response);
      await expectLater(
        _api(client).listPullRequests(_slug, token: 't'),
        throwsA(
          isA<GitHubApiException>().having((e) => e.kind, 'kind', kind),
        ),
      );
    }

    await expectKind(http.Response('{}', 401), GitHubApiErrorKind.auth);
    await expectKind(
      http.Response('{}', 403, headers: {'x-ratelimit-remaining': '0'}),
      GitHubApiErrorKind.rateLimit,
    );
    await expectKind(http.Response('{}', 403), GitHubApiErrorKind.auth);
    await expectKind(http.Response('{}', 404), GitHubApiErrorKind.notFound);
    await expectKind(http.Response('boom', 500), GitHubApiErrorKind.network);
  });

  test('maps transport exceptions to network', () async {
    final client = MockClient((_) async {
      throw http.ClientException('connection reset');
    });
    await expectLater(
      _api(client).listPullRequests(_slug, token: 't'),
      throwsA(
        isA<GitHubApiException>()
            .having((e) => e.kind, 'kind', GitHubApiErrorKind.network),
      ),
    );
  });
}
```

- [ ] **Step 2: Run — fails to compile**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/github/github_rest_api_test.dart`

- [ ] **Step 3: Implement** `lib/infrastructure/github/github_rest_api.dart`:

```dart
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:gitopen/application/github/github_api.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:http/http.dart' as http;

/// GitHub REST v3 implementation of [GitHubApi]. The [http.Client] is
/// injectable so tests drive it with `MockClient` (same pattern as the
/// device-flow poller).
final class GitHubRestApi implements GitHubApi {
  GitHubRestApi({http.Client? client, this.baseUrl = 'https://api.github.com'})
      : _client = client ?? http.Client();
  final http.Client _client;
  final String baseUrl;

  @override
  Future<List<PullRequestInfo>> listPullRequests(
    RepoSlug slug, {
    required String token,
  }) async {
    final body = await _get(
      '/repos/${slug.owner}/${slug.repo}/pulls',
      token,
      query: {'state': 'open', 'per_page': '50'},
    );
    return [
      for (final pr in body as List<dynamic>)
        _parsePullRequest(pr as Map<String, dynamic>),
    ];
  }

  @override
  Future<List<WorkflowRunInfo>> listWorkflowRuns(
    RepoSlug slug, {
    required String token,
    String? branch,
  }) async {
    final body = await _get(
      '/repos/${slug.owner}/${slug.repo}/actions/runs',
      token,
      query: {'per_page': '30', if (branch != null) 'branch': branch},
    );
    final runs = (body as Map<String, dynamic>)['workflow_runs'];
    return [
      for (final run in (runs as List<dynamic>? ?? const []))
        _parseRun(run as Map<String, dynamic>),
    ];
  }

  @override
  Future<CheckSummary> prChecks(
    RepoSlug slug,
    String headSha, {
    required String token,
  }) async {
    final body = await _get(
      '/repos/${slug.owner}/${slug.repo}/commits/$headSha/check-runs',
      token,
      query: {'per_page': '100'},
    );
    final runs =
        (body as Map<String, dynamic>)['check_runs'] as List<dynamic>? ??
            const [];
    var succeeded = 0;
    var failed = 0;
    var pending = 0;
    for (final raw in runs) {
      final run = raw as Map<String, dynamic>;
      if (run['status'] != 'completed') {
        pending++;
        continue;
      }
      switch (run['conclusion']) {
        case 'success' || 'neutral' || 'skipped':
          succeeded++;
        default:
          failed++;
      }
    }
    return CheckSummary(
      total: runs.length,
      succeeded: succeeded,
      failed: failed,
      pending: pending,
    );
  }

  PullRequestInfo _parsePullRequest(Map<String, dynamic> pr) {
    final head = pr['head'] as Map<String, dynamic>? ?? const {};
    return PullRequestInfo(
      number: pr['number'] as int,
      title: pr['title'] as String? ?? '',
      author: (pr['user'] as Map<String, dynamic>?)?['login'] as String? ?? '',
      isDraft: pr['draft'] as bool? ?? false,
      headRef: head['ref'] as String? ?? '',
      headSha: head['sha'] as String? ?? '',
      htmlUrl: pr['html_url'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(pr['updated_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  WorkflowRunInfo _parseRun(Map<String, dynamic> run) {
    return WorkflowRunInfo(
      id: run['id'] as int,
      name: run['name'] as String? ?? 'workflow',
      headBranch: run['head_branch'] as String? ?? '',
      status: run['status'] as String? ?? 'completed',
      conclusion: run['conclusion'] as String?,
      htmlUrl: run['html_url'] as String? ?? '',
      createdAt:
          DateTime.tryParse(run['created_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          DateTime.tryParse(run['updated_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  /// GET [path] with auth headers; decodes JSON and maps every failure shape
  /// to a typed [GitHubApiException].
  Future<dynamic> _get(
    String path,
    String token, {
    Map<String, String> query = const {},
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $token',
        'X-GitHub-Api-Version': '2022-11-28',
      });
    } on http.ClientException catch (e) {
      throw GitHubApiException(GitHubApiErrorKind.network, e.message);
    } on SocketException catch (e) {
      throw GitHubApiException(GitHubApiErrorKind.network, e.message);
    }
    switch (response.statusCode) {
      case 200:
        return jsonDecode(response.body);
      case 401:
        throw const GitHubApiException(
          GitHubApiErrorKind.auth,
          'GitHub rejected the credential (401). Sign in again.',
        );
      case 403 || 429:
        if (response.headers['x-ratelimit-remaining'] == '0') {
          throw const GitHubApiException(
            GitHubApiErrorKind.rateLimit,
            'GitHub API rate limit reached. Try again later.',
          );
        }
        throw const GitHubApiException(
          GitHubApiErrorKind.auth,
          'GitHub denied access (403). The token may lack scopes.',
        );
      case 404:
        throw const GitHubApiException(
          GitHubApiErrorKind.notFound,
          'Not found on GitHub (404).',
        );
      default:
        throw GitHubApiException(
          GitHubApiErrorKind.network,
          'GitHub API returned ${response.statusCode}.',
        );
    }
  }
}
```

- [ ] **Step 4: Run — tests pass; analyze clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/github/github_rest_api_test.dart` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 5: Commit**

```powershell
git add lib/infrastructure/github test/infrastructure/github
git commit -m "feat(phase5): GitHub REST v3 implementation with typed errors"
```

---

### Task 4: `fetchRefspec` write op

**Files:**
- Modify: `lib/application/git/git_write_operations.dart:141-146`
- Modify: `lib/infrastructure/git/git_cli_sync_writer.dart:21-32`
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart:314-319`
- Test: `test/infrastructure/git/git_cli_write_operations_fetch_test.dart` (append)

- [ ] **Step 1: Write the failing real-git test** — append inside `main()` of the fetch test file (check its imports/helpers first and follow them; the code below is self-contained except `RepoFixture`):

```dart
  test('fetchRefspec materialises a remote ref as a local branch', () async {
    // Origin with an extra non-branch ref (like GitHub's refs/pull/N/head).
    final origin = await RepoFixture.withLinearHistory(2);
    final local = await RepoFixture.empty();
    try {
      await Process.run(
        'git',
        ['update-ref', 'refs/pull/3/head', origin.headSha],
        workingDirectory: origin.path,
      );
      final originUrl = origin.path.replaceAll(r'\', '/');
      await Process.run(
        'git',
        ['remote', 'add', 'origin', originUrl],
        workingDirectory: local.path,
      );

      final sut = GitCliWriteOperations();
      final repo = RepoLocation(RepoId.newId(), local.path, 'fx');
      await sut
          .fetchRefspec(repo, 'origin', '+pull/3/head:refs/heads/pr/3')
          .drain<void>();

      final sha = await Process.run(
        'git',
        ['rev-parse', 'refs/heads/pr/3'],
        workingDirectory: local.path,
      );
      expect((sha.stdout as String).trim(), origin.headSha);
    } finally {
      await origin.dispose();
      await local.dispose();
    }
  });
```

- [ ] **Step 2: Run — fails to compile** (`fetchRefspec` undefined)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_write_operations_fetch_test.dart`

- [ ] **Step 3: Implement.** Interface — add right after `fetch` in `git_write_operations.dart`:

```dart
  /// `git fetch <remote> <refspec>` — fetches one explicit refspec, e.g.
  /// `'+pull/42/head:refs/heads/pr/42'` to materialise a GitHub PR head as a
  /// (force-updated) local branch.
  Stream<GitProgress> fetchRefspec(
    RepoLocation r,
    String remote,
    String refspec, {
    AuthSpec? auth,
  });
```

Sync writer (`git_cli_sync_writer.dart`) — add right after its `fetch`:

```dart
  Stream<GitProgress> fetchRefspec(RepoLocation r, String remote,
      String refspec, {AuthSpec? auth}) async* {
    final args = <String>['fetch', '--progress', remote, refspec];
    await for (final p in _runProgressStream(r.path, args, auth: auth)) {
      yield p;
    }
  }
```

Facade (`git_cli_write_operations.dart`) — add after the `fetch` delegation:

```dart
  @override
  Stream<GitProgress> fetchRefspec(
    RepoLocation r,
    String remote,
    String refspec, {
    AuthSpec? auth,
  }) => _sync.fetchRefspec(r, remote, refspec, auth: auth);
```

- [ ] **Step 4: Run — fetch tests pass; analyze clean** (the analyzer will flag any other `GitWriteOperations` implementor/fake missing the member — fix those by adding the same delegation or relying on existing `noSuchMethod` fakes)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_write_operations_fetch_test.dart` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 5: Commit**

```powershell
git add lib/application/git/git_write_operations.dart lib/infrastructure/git/git_cli_sync_writer.dart lib/infrastructure/git/git_cli_write_operations.dart test/infrastructure/git/git_cli_write_operations_fetch_test.dart
git commit -m "feat(phase5): fetchRefspec write op for PR head fetching"
```

---

### Task 5: `checkoutPullRequest` action (service + controller)

**Files:**
- Modify: `lib/application/git/git_actions_service.dart` (after `fetchRemote`)
- Modify: `lib/ui/git/git_actions_controller.dart` (after `fetchRemote`)
- Test: `test/application/git/git_actions_service_github_test.dart` (new)

- [ ] **Step 1: Write the failing service test** at `test/application/git/git_actions_service_github_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/git/auth_failure_classifier.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

final class _FakeWrite implements GitWriteOperations {
  final calls = <String>[];
  bool failFetch = false;

  @override
  Stream<GitProgress> fetchRefspec(
    RepoLocation r,
    String remote,
    String refspec, {
    AuthSpec? auth,
  }) {
    calls.add('fetch $remote $refspec');
    if (failFetch) {
      return Stream.error(Exception('fatal: could not read from remote'));
    }
    return const Stream.empty();
  }

  @override
  Future<GitResult<void>> checkout(
    RepoLocation r,
    String ref, {
    bool force = false,
  }) async {
    calls.add('checkout $ref');
    return const GitSuccess(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _NoPrompt implements AuthPrompt {
  @override
  Future<AuthProfile?> forAccount(
    RepoLocation repo,
    AuthFailureReason reason,
  ) async => null;
}

final class _NullSink implements ProgressSink {
  @override
  String start(OpKind kind, String label, {RepoLocation? repo}) => 'op';
  @override
  void progress(String id, double? fraction, String phase) {}
  @override
  void success(String id) {}
  @override
  void failure(String id, String message) {}
}

void main() {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');

  GitActionsService service(_FakeWrite write) => GitActionsService(
        write: write,
        resolveProfile: (_) async => null,
        errorText: (e) => e.toString(),
      );

  test('checkoutPullRequest force-fetches pull/<n>/head then checks out',
      () async {
    final write = _FakeWrite();
    final result = await service(write).checkoutPullRequest(
      repo,
      42,
      prompt: _NoPrompt(),
      progress: _NullSink(),
    );
    expect(result.outcome, ActionOutcome.success);
    expect(write.calls, [
      'fetch origin +pull/42/head:refs/heads/pr/42',
      'checkout pr/42',
    ]);
  });

  test('a failed fetch stops before checkout', () async {
    final write = _FakeWrite()..failFetch = true;
    final result = await service(write).checkoutPullRequest(
      repo,
      42,
      prompt: _NoPrompt(),
      progress: _NullSink(),
    );
    expect(result.outcome, ActionOutcome.failed);
    expect(write.calls, ['fetch origin +pull/42/head:refs/heads/pr/42']);
  });
}
```

NOTE: check `GitSuccess`'s constructor in `lib/application/git/git_result.dart` — if `GitSuccess(null)` does not compile (e.g. it is `GitSuccess<void>` with a positional value), mirror whatever the existing service tests in `test/application/git/git_actions_service_local_test.dart` do for void successes.

- [ ] **Step 2: Run — fails to compile** (`checkoutPullRequest` undefined)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/git/git_actions_service_github_test.dart`

- [ ] **Step 3: Implement.** Service — add after `fetchRemote` in `git_actions_service.dart`:

```dart
  /// Materialises GitHub PR [number] as the local branch `pr/<number>`
  /// (forced fetch of `pull/<number>/head`) and checks it out. The fetch has
  /// progress + auth-retry; a fetch failure stops before the checkout.
  Future<ActionResult> checkoutPullRequest(
    RepoLocation repo,
    int number, {
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) async {
    final branch = 'pr/$number';
    final fetched = await _runStream(
      OpKind.fetch,
      'Fetching PR #$number',
      repo,
      (auth) => _write.fetchRefspec(
        repo,
        'origin',
        '+pull/$number/head:refs/heads/$branch',
        auth: auth,
      ),
      prompt: prompt,
      progress: progress,
    );
    if (fetched.outcome != ActionOutcome.success) return fetched;
    return _simple('Checkout', _write.checkout(repo, branch));
  }
```

Controller — add after `fetchRemote` in `git_actions_controller.dart`:

```dart
  /// Fetches GitHub PR [number] into `pr/<number>` and checks it out.
  Future<ActionResult> checkoutPullRequest(
    BuildContext context,
    RepoLocation repo,
    int number,
  ) {
    return _run(
      context,
      repo,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .checkoutPullRequest(repo, number, prompt: prompt, progress: progress),
    );
  }
```

- [ ] **Step 4: Run — service tests pass (new + existing); analyze clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/git` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 5: Commit**

```powershell
git add lib/application/git/git_actions_service.dart lib/ui/git/git_actions_controller.dart test/application/git/git_actions_service_github_test.dart
git commit -m "feat(phase5): checkoutPullRequest action with progress + auth-retry"
```

---

### Task 6: Providers wiring + GitHub view slot

**Files:**
- Modify: `lib/application/providers.dart` (new providers; reuse reader in `authResolverProvider`)
- Modify: `lib/application/main_view_provider.dart`
- Modify: `lib/ui/shell/view_selector.dart`
- Modify: `lib/main.dart:304` (`ViewSelector`) and `:309-314` (`_RepoBody` view switch)

- [ ] **Step 1: Providers.** In `providers.dart` add (plus imports for `GitHubApi`, `GitHubRestApi`, `RepoSlug`, `githubSlugFromRemoteUrl`, `RemoteUrlReader` is already exported via auth_resolver import — add `import 'package:gitopen/application/auth/auth_resolver.dart';`, `import 'package:gitopen/application/github/github_api.dart';`, `import 'package:gitopen/application/github/github_models.dart';`, `import 'package:gitopen/application/github/github_slug.dart';`, `import 'package:gitopen/infrastructure/github/github_rest_api.dart';`):

```dart
/// Reads a repo's remote URL via the git CLI (shared by the auth resolver
/// and GitHub-ness detection).
final remoteUrlReaderProvider = Provider<RemoteUrlReader>((ref) {
  return GitRemoteUrlReader(runner: ref.watch(gitProcessRunnerProvider));
});

/// GitHub REST client (token passed per call).
final gitHubApiProvider = Provider<GitHubApi>((ref) => GitHubRestApi());

/// The repo's GitHub `owner/repo` slug, or null when `origin` is missing or
/// not a github.com URL — null hides the GitHub view.
final AutoDisposeFutureProviderFamily<RepoSlug?, RepoLocation>
    githubSlugProvider =
    FutureProvider.family.autoDispose<RepoSlug?, RepoLocation>(
  (ref, repo) async {
    final url =
        await ref.watch(remoteUrlReaderProvider).remoteUrl(repo, 'origin');
    return url == null ? null : githubSlugFromRemoteUrl(url);
  },
);
```

and change `authResolverProvider`'s construction to reuse it:

```dart
    remoteUrl: ref.watch(remoteUrlReaderProvider),
```

- [ ] **Step 2: View enum.** `main_view_provider.dart`:

```dart
enum MainView { graph, changes, github }
```

- [ ] **Step 3: View selector.** `view_selector.dart` — the widget gains the repo and shows the GitHub segment only for GitHub repos:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/main_view_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Segmented toggle between the commit-graph view, the working-copy changes
/// view and (for github.com origins) the GitHub PRs/Actions view. Lives at
/// the top of the main panel area.
class ViewSelector extends ConsumerWidget {
  const ViewSelector({required this.repo, super.key});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final current = ref.watch(mainViewProvider);
    final isGitHub =
        ref.watch(githubSlugProvider(repo)).valueOrNull != null;
    return Container(
      height: 30,
      color: palette.bg2,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _SegmentButton(
            label: 'Graph',
            icon: Icons.account_tree_outlined,
            selected: current == MainView.graph,
            onTap: () =>
                ref.read(mainViewProvider.notifier).state = MainView.graph,
          ),
          const SizedBox(width: 4),
          _SegmentButton(
            label: 'Changes',
            icon: Icons.edit_note,
            selected: current == MainView.changes,
            onTap: () =>
                ref.read(mainViewProvider.notifier).state = MainView.changes,
          ),
          if (isGitHub) ...[
            const SizedBox(width: 4),
            _SegmentButton(
              label: 'GitHub',
              icon: Icons.cloud_outlined,
              selected: current == MainView.github,
              onTap: () =>
                  ref.read(mainViewProvider.notifier).state = MainView.github,
            ),
          ],
        ],
      ),
    );
  }
}
```

(`_SegmentButton` stays unchanged.)

- [ ] **Step 4: Shell.** In `main.dart` `_RepoBody.build`: replace `const ViewSelector(),` with `ViewSelector(repo: repo),` and extend the view switch (import `package:gitopen/ui/github/github_panel.dart` — created next task; to keep this task compiling, do Steps 1–3 now and fold Step 4 into Task 7 Step 3 if you prefer strict per-commit compilation — otherwise create a stub panel now):

```dart
            child: hasConflict
                ? ConflictResolutionPanel(repo: repo)
                : view == MainView.changes
                    ? WorkingCopyPanel(repo: repo)
                    : view == MainView.github
                        ? GitHubPanel(repo: repo)
                        : VerticalSplitter(
                            top: CommitGraphPanel(repo: repo),
                            bottom: BottomPanel(repo: repo),
                          ),
```

To keep this task self-contained and green, create the minimal placeholder `lib/ui/github/github_panel.dart` now (Task 7 replaces it wholesale):

```dart
import 'package:flutter/material.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// GitHub PRs/Actions view — full implementation lands with the panel task.
class GitHubPanel extends StatelessWidget {
  const GitHubPanel({required this.repo, super.key});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

- [ ] **Step 5: Run — analyze clean; full ui test dir still green**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui test/application/providers_test.dart`

- [ ] **Step 6: Commit**

```powershell
git add lib/application/providers.dart lib/application/main_view_provider.dart lib/ui/shell/view_selector.dart lib/main.dart lib/ui/github/github_panel.dart
git commit -m "feat(phase5): GitHub view slot + slug/api providers"
```

---

### Task 7: The GitHub panel

**Files:**
- Rewrite: `lib/ui/github/github_panel.dart`
- Test: `test/ui/github/github_panel_test.dart` (new)

- [ ] **Step 1: Write the failing widget tests** at `test/ui/github/github_panel_test.dart`:

```dart
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
  }) async =>
      const CheckSummary(total: 2, succeeded: 2, failed: 0, pending: 0);
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
  final profile = AuthProfile(
    id: 'p1',
    host: 'github.com',
    username: 'ada',
    spec: const AuthGitHubOauth('tok'),
  );

  testWidgets('no usable token shows the sign-in CTA', (tester) async {
    await _pump(tester, repo: repo, api: _FakeApi());
    expect(find.text('Sign in with GitHub'), findsOneWidget);
  });

  testWidgets('lists open pull requests with draft badge and checks',
      (tester) async {
    await _pump(tester, repo: repo, api: _FakeApi(), profile: profile);
    expect(find.text('#12'), findsOneWidget);
    expect(find.text('Improve the widget'), findsOneWidget);
    expect(find.text('DRAFT'), findsOneWidget);
    expect(find.text('ada'), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget); // checks chip
  });

  testWidgets('Actions tab lists runs for the current branch',
      (tester) async {
    await _pump(tester, repo: repo, api: _FakeApi(), profile: profile);
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('CI GitOpen'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.textContaining('3m 30s'), findsOneWidget);
  });

  testWidgets('a network error renders inline with a Retry button',
      (tester) async {
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
```

- [ ] **Step 2: Run — fails** (stub panel renders nothing)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/github/github_panel_test.dart`

- [ ] **Step 3: Implement the panel** — replace `lib/ui/github/github_panel.dart` wholesale:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_api.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/auth_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

typedef _ApiKey = ({RepoSlug slug, String token});

final AutoDisposeFutureProviderFamily<List<PullRequestInfo>, _ApiKey>
    _prsProvider =
    FutureProvider.family.autoDispose<List<PullRequestInfo>, _ApiKey>(
  (ref, key) =>
      ref.watch(gitHubApiProvider).listPullRequests(key.slug, token: key.token),
);

final AutoDisposeFutureProviderFamily<List<WorkflowRunInfo>,
        ({RepoSlug slug, String token, String? branch})> _runsProvider =
    FutureProvider.family.autoDispose<List<WorkflowRunInfo>,
        ({RepoSlug slug, String token, String? branch})>(
  (ref, key) => ref
      .watch(gitHubApiProvider)
      .listWorkflowRuns(key.slug, token: key.token, branch: key.branch),
);

final AutoDisposeFutureProviderFamily<CheckSummary,
        ({RepoSlug slug, String token, String sha})> _checksProvider =
    FutureProvider.family.autoDispose<CheckSummary,
        ({RepoSlug slug, String token, String sha})>(
  (ref, key) => ref
      .watch(gitHubApiProvider)
      .prChecks(key.slug, key.sha, token: key.token),
);

/// GitHub view for a github.com repo: open Pull Requests (with per-PR
/// checkout + check status) and recent Actions runs for the current branch.
/// No usable token → inline device-flow sign-in CTA; API failures render
/// inline and never block local git work.
class GitHubPanel extends ConsumerStatefulWidget {
  const GitHubPanel({required this.repo, super.key});
  final RepoLocation repo;

  @override
  ConsumerState<GitHubPanel> createState() => _GitHubPanelState();
}

class _GitHubPanelState extends ConsumerState<GitHubPanel> {
  String _tab = 'prs';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final slug = ref.watch(githubSlugProvider(widget.repo)).valueOrNull;
    if (slug == null) {
      return Center(
        child: Text(
          'Not a GitHub repository',
          style: TextStyle(
            color: palette.fg3,
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    final profileAsync = ref.watch(repoActiveProfileProvider(widget.repo));
    if (profileAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final token = githubTokenOf(profileAsync.valueOrNull?.spec);
    if (token == null) {
      return _SignInCta(repo: widget.repo);
    }
    return Column(
      children: [
        _TabsBar(active: _tab, onSelect: (v) => setState(() => _tab = v)),
        Expanded(
          child: _tab == 'prs'
              ? _PullRequestsTab(repo: widget.repo, slug: slug, token: token)
              : _ActionsTab(repo: widget.repo, slug: slug, token: token),
        ),
      ],
    );
  }
}

class _TabsBar extends StatelessWidget {
  const _TabsBar({required this.active, required this.onSelect});
  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      color: palette.bg3,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _Tab(
            label: 'Pull Requests',
            value: 'prs',
            active: active,
            onSelect: onSelect,
          ),
          _Tab(
            label: 'Actions',
            value: 'actions',
            active: active,
            onSelect: onSelect,
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.value,
    required this.active,
    required this.onSelect,
  });
  final String label;
  final String value;
  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isActive = active == value;
    return InkWell(
      onTap: () => onSelect(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? palette.accentCurrent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? palette.fg0 : palette.fg1,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInCta extends ConsumerWidget {
  const _SignInCta({required this.repo});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 32, color: palette.fg3),
          const SizedBox(height: 10),
          Text(
            'Sign in to see pull requests and workflow runs.',
            style: TextStyle(color: palette.fg2, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.login, size: 14),
            label: const Text('Sign in with GitHub'),
            onPressed: () async {
              final profile = await AuthDialog.show(context, 'github.com');
              if (profile == null) return;
              await ref
                  .read(appSettingsProvider.notifier)
                  .setAuthBinding(repo.id.value, profile.id);
              ref.invalidate(repoActiveProfileProvider(repo));
            },
          ),
        ],
      ),
    );
  }
}

class _ApiError extends StatelessWidget {
  const _ApiError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final message = error is GitHubApiException
        ? error.toString()
        : 'GitHub request failed: $error';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.fg2, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _PullRequestsTab extends ConsumerWidget {
  const _PullRequestsTab({
    required this.repo,
    required this.slug,
    required this.token,
  });
  final RepoLocation repo;
  final RepoSlug slug;
  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final key = (slug: slug, token: token);
    final async = ref.watch(_prsProvider(key));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          _ApiError(error: e, onRetry: () => ref.invalidate(_prsProvider(key))),
      data: (prs) => prs.isEmpty
          ? Center(
              child: Text(
                'No open pull requests',
                style: TextStyle(
                  color: palette.fg3,
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: prs.length,
              itemBuilder: (_, i) => _PullRequestRow(
                repo: repo,
                slug: slug,
                token: token,
                pr: prs[i],
              ),
            ),
    );
  }
}

class _PullRequestRow extends ConsumerWidget {
  const _PullRequestRow({
    required this.repo,
    required this.slug,
    required this.token,
    required this.pr,
  });
  final RepoLocation repo;
  final RepoSlug slug;
  final String token;
  final PullRequestInfo pr;

  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          Text(
            '#${pr.number}',
            style: TextStyle(
              color: palette.accentRemote,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 10),
          if (pr.isDraft) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: palette.fg3.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'DRAFT',
                style: TextStyle(
                  color: palette.fg2,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pr.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.fg0, fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  pr.author,
                  style: TextStyle(color: palette.fg3, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CheckChip(slug: slug, token: token, sha: pr.headSha),
          const SizedBox(width: 8),
          Text(
            _dateFmt.format(pr.updatedAt.toLocal()),
            style: TextStyle(color: palette.fg3, fontSize: 10.5),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Checkout PR as pr/${pr.number}',
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: () => ref
                  .read(gitActionsControllerProvider)
                  .checkoutPullRequest(context, repo, pr.number),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.call_split, size: 15, color: palette.fg1),
              ),
            ),
          ),
          Tooltip(
            message: 'Open on GitHub',
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: () => launchUrl(
                Uri.parse(pr.htmlUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child:
                    Icon(Icons.open_in_new, size: 14, color: palette.fg1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckChip extends ConsumerWidget {
  const _CheckChip({required this.slug, required this.token, required this.sha});
  final RepoSlug slug;
  final String token;
  final String sha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async =
        ref.watch(_checksProvider((slug: slug, token: token, sha: sha)));
    final summary = async.valueOrNull;
    if (summary == null || summary.state == CheckState.none) {
      return const SizedBox.shrink();
    }
    final (icon, color) = switch (summary.state) {
      CheckState.success => (Icons.check_circle_outline, palette.accentCurrent),
      CheckState.failure => (Icons.cancel_outlined, palette.accentErr),
      CheckState.pending => (Icons.schedule, palette.accentWarn),
      CheckState.none => (Icons.remove, palette.fg3),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          '${summary.succeeded}/${summary.total}',
          style: TextStyle(color: color, fontSize: 11),
        ),
      ],
    );
  }
}

class _ActionsTab extends ConsumerWidget {
  const _ActionsTab({
    required this.repo,
    required this.slug,
    required this.token,
  });
  final RepoLocation repo;
  final RepoSlug slug;
  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final branch =
        ref.watch(repoStatusProvider(repo)).valueOrNull?.currentBranch;
    final key = (slug: slug, token: token, branch: branch);
    final async = ref.watch(_runsProvider(key));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ApiError(
        error: e,
        onRetry: () => ref.invalidate(_runsProvider(key)),
      ),
      data: (runs) => runs.isEmpty
          ? Center(
              child: Text(
                branch == null
                    ? 'No workflow runs'
                    : 'No workflow runs for $branch',
                style: TextStyle(
                  color: palette.fg3,
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: runs.length,
              itemBuilder: (_, i) => _RunRow(run: runs[i]),
            ),
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run});
  final WorkflowRunInfo run;

  String get _durationLabel {
    final d = run.duration;
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (icon, color) = !run.isCompleted
        ? (Icons.timelapse, palette.accentWarn)
        : switch (run.conclusion) {
            'success' => (Icons.check_circle_outline, palette.accentCurrent),
            'failure' => (Icons.cancel_outlined, palette.accentErr),
            _ => (Icons.remove_circle_outline, palette.fg3),
          };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              run.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.fg0, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            run.headBranch,
            style: TextStyle(color: palette.accentRemote, fontSize: 11),
          ),
          const SizedBox(width: 10),
          if (run.isCompleted)
            Text(
              _durationLabel,
              style: TextStyle(color: palette.fg3, fontSize: 11),
            ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Open on GitHub',
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: () => launchUrl(
                Uri.parse(run.htmlUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child:
                    Icon(Icons.open_in_new, size: 14, color: palette.fg1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run — panel tests pass; analyze clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/github/github_panel_test.dart` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/github/github_panel.dart test/ui/github/github_panel_test.dart
git commit -m "feat(phase5): GitHub panel - pull requests and workflow runs"
```

---

### Task 8: Verification and PR

- [ ] **Step 1: Bump version** in `pubspec.yaml`: `0.1.19+20` → `0.1.20+21`.
- [ ] **Step 2: Format touched files only**: `git diff main...HEAD --name-only` filtered to `.dart`, then `dart.bat format @files`.
- [ ] **Step 3: Full verification**

```powershell
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test -j 2
& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze
git diff --check
```

Expected: full suite green (623 pre-S3 + ~15 new), analyze clean. Flake note: the two known real-git fixture tests may flake under full-suite load — rerun the single file to confirm.

- [ ] **Step 4: Commit, push, PR, merge on green**

```powershell
gh auth switch --hostname github.com --user zN3utr4l
git add -A
git commit -m "chore(phase5): bump version to 0.1.20 + format touched files"
git push -u origin feat/phase5-s3-github-prs-actions
gh pr create --repo zN3utr4l/GitOpen --base main --title "feat(phase5): S3 - GitHub PRs + Actions" --body "<summary + spec link docs/superpowers/specs/2026-06-11-phase5-complete-beautiful-design.md>"
gh pr checks --repo zN3utr4l/GitOpen --watch   # merge with: gh pr merge --repo zN3utr4l/GitOpen --merge --delete-branch
```
