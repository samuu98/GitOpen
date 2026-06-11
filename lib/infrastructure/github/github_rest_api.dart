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
    final query = {'per_page': '30'};
    if (branch != null) {
      query['branch'] = branch;
    }
    final body = await _get(
      '/repos/${slug.owner}/${slug.repo}/actions/runs',
      token,
      query: query,
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
      updatedAt: DateTime.tryParse(pr['updated_at'] as String? ?? '') ??
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
      createdAt: DateTime.tryParse(run['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.tryParse(run['updated_at'] as String? ?? '') ??
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
