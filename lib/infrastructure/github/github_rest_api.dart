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

  @override
  Future<PullRequestDetail> getPullRequest(
    RepoSlug slug,
    int number, {
    required String token,
  }) async {
    final body = await _get(_pullPath(slug, number), token);
    return _parsePullRequestDetail(body as Map<String, dynamic>);
  }

  @override
  Future<List<PullRequestFile>> listPullRequestFiles(
    RepoSlug slug,
    int number, {
    required String token,
  }) async {
    final body = await _get('${_pullPath(slug, number)}/files', token);
    return [
      for (final file in body as List<dynamic>)
        _parsePullRequestFile(file as Map<String, dynamic>),
    ];
  }

  @override
  Future<List<PullRequestReview>> listPullRequestReviews(
    RepoSlug slug,
    int number, {
    required String token,
  }) async {
    final body = await _get('${_pullPath(slug, number)}/reviews', token);
    return [
      for (final review in body as List<dynamic>)
        _parseReview(review as Map<String, dynamic>),
    ];
  }

  @override
  Future<List<PullRequestComment>> listPullRequestReviewComments(
    RepoSlug slug,
    int number, {
    required String token,
  }) async {
    final body = await _get('${_pullPath(slug, number)}/comments', token);
    return [
      for (final comment in body as List<dynamic>)
        _parseReviewComment(comment as Map<String, dynamic>),
    ];
  }

  @override
  Future<List<IssueCommentInfo>> listPullRequestIssueComments(
    RepoSlug slug,
    int number, {
    required String token,
  }) async {
    final body = await _get(
      '${_repoPath(slug)}/issues/$number/comments',
      token,
    );
    return [
      for (final comment in body as List<dynamic>)
        _parseIssueComment(comment as Map<String, dynamic>),
    ];
  }

  @override
  Future<PullRequestDetail> createPullRequest(
    RepoSlug slug,
    CreatePullRequestRequest request, {
    required String token,
  }) async {
    final body = await _post(
      '${_repoPath(slug)}/pulls',
      token,
      body: request.toJson(),
    );
    return _parsePullRequestDetail(body as Map<String, dynamic>);
  }

  @override
  Future<PullRequestDetail> updatePullRequest(
    RepoSlug slug,
    int number,
    UpdatePullRequestRequest request, {
    required String token,
  }) async {
    final body = await _patch(
      _pullPath(slug, number),
      token,
      body: request.toJson(),
    );
    return _parsePullRequestDetail(body as Map<String, dynamic>);
  }

  @override
  Future<PullRequestDetail> markPullRequestReadyForReview(
    RepoSlug slug,
    int number, {
    required String token,
  }) async {
    final detail = await getPullRequest(slug, number, token: token);
    await _graphql(
      token,
      query: r'''
mutation MarkReady($id: ID!) {
  markPullRequestReadyForReview(input: {pullRequestId: $id}) {
    pullRequest { id }
  }
}
''',
      variables: {'id': detail.nodeId},
    );
    return getPullRequest(slug, number, token: token);
  }

  @override
  Future<void> mergePullRequest(
    RepoSlug slug,
    int number,
    MergePullRequestRequest request, {
    required String token,
  }) async {
    await _put(
      '${_pullPath(slug, number)}/merge',
      token,
      body: request.toJson(),
    );
  }

  @override
  Future<IssueCommentInfo> createIssueComment(
    RepoSlug slug,
    int number,
    String body, {
    required String token,
  }) async {
    final response = await _post(
      '${_repoPath(slug)}/issues/$number/comments',
      token,
      body: {'body': body},
    );
    return _parseIssueComment(response as Map<String, dynamic>);
  }

  @override
  Future<PullRequestReview> createReview(
    RepoSlug slug,
    int number,
    SubmitReviewRequest request, {
    required String token,
  }) async {
    final body = await _post(
      '${_pullPath(slug, number)}/reviews',
      token,
      body: request.toJson(),
    );
    return _parseReview(body as Map<String, dynamic>);
  }

  @override
  Future<PullRequestComment> createReviewCommentReply(
    RepoSlug slug,
    int number,
    int commentId,
    String body, {
    required String token,
  }) async {
    final response = await _post(
      '${_pullPath(slug, number)}/comments/$commentId/replies',
      token,
      body: {'body': body},
    );
    return _parseReviewComment(response as Map<String, dynamic>);
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

  PullRequestDetail _parsePullRequestDetail(Map<String, dynamic> pr) {
    final head = pr['head'] as Map<String, dynamic>? ?? const {};
    final base = pr['base'] as Map<String, dynamic>? ?? const {};
    return PullRequestDetail(
      number: pr['number'] as int,
      nodeId: pr['node_id'] as String? ?? '',
      title: pr['title'] as String? ?? '',
      body: pr['body'] as String? ?? '',
      author: (pr['user'] as Map<String, dynamic>?)?['login'] as String? ?? '',
      state: pr['state'] as String? ?? '',
      isDraft: pr['draft'] as bool? ?? false,
      mergeable: pr['mergeable'] as bool?,
      mergeStateStatus:
          pr['merge_state_status'] as String? ??
          pr['mergeable_state'] as String? ??
          '',
      baseRef: base['ref'] as String? ?? '',
      headRef: head['ref'] as String? ?? '',
      headSha: head['sha'] as String? ?? '',
      htmlUrl: pr['html_url'] as String? ?? '',
      createdAt: _parseDate(pr['created_at'] as String?),
      updatedAt: _parseDate(pr['updated_at'] as String?),
    );
  }

  PullRequestFile _parsePullRequestFile(Map<String, dynamic> file) {
    return PullRequestFile(
      filename: file['filename'] as String? ?? '',
      status: file['status'] as String? ?? '',
      additions: file['additions'] as int? ?? 0,
      deletions: file['deletions'] as int? ?? 0,
      changes: file['changes'] as int? ?? 0,
      patch: file['patch'] as String? ?? '',
    );
  }

  PullRequestReview _parseReview(Map<String, dynamic> review) {
    return PullRequestReview(
      id: review['id'] as int? ?? 0,
      user:
          (review['user'] as Map<String, dynamic>?)?['login'] as String? ?? '',
      state: review['state'] as String? ?? '',
      body: review['body'] as String? ?? '',
      submittedAt: _parseOptionalDate(review['submitted_at'] as String?),
      htmlUrl: review['html_url'] as String? ?? '',
    );
  }

  PullRequestComment _parseReviewComment(Map<String, dynamic> comment) {
    return PullRequestComment(
      id: comment['id'] as int? ?? 0,
      user:
          (comment['user'] as Map<String, dynamic>?)?['login'] as String? ?? '',
      body: comment['body'] as String? ?? '',
      path: comment['path'] as String? ?? '',
      side: comment['side'] as String? ?? 'RIGHT',
      line: comment['line'] as int?,
      position: comment['position'] as int?,
      inReplyToId: comment['in_reply_to_id'] as int?,
      createdAt: _parseDate(comment['created_at'] as String?),
      updatedAt: _parseDate(comment['updated_at'] as String?),
      htmlUrl: comment['html_url'] as String? ?? '',
    );
  }

  IssueCommentInfo _parseIssueComment(Map<String, dynamic> comment) {
    return IssueCommentInfo(
      id: comment['id'] as int? ?? 0,
      user:
          (comment['user'] as Map<String, dynamic>?)?['login'] as String? ?? '',
      body: comment['body'] as String? ?? '',
      createdAt: _parseDate(comment['created_at'] as String?),
      updatedAt: _parseDate(comment['updated_at'] as String?),
      htmlUrl: comment['html_url'] as String? ?? '',
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

  String _repoPath(RepoSlug slug) => '/repos/${slug.owner}/${slug.repo}';

  String _pullPath(RepoSlug slug, int number) =>
      '${_repoPath(slug)}/pulls/$number';

  DateTime _parseDate(String? raw) =>
      DateTime.tryParse(raw ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  DateTime? _parseOptionalDate(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw);

  /// GET [path] with auth headers; decodes JSON and maps every failure shape
  /// to a typed [GitHubApiException].
  Future<dynamic> _get(
    String path,
    String token, {
    Map<String, String> query = const {},
  }) async {
    return _request('GET', path, token, query: query);
  }

  Future<dynamic> _post(
    String path,
    String token, {
    Object? body,
    Map<String, String> query = const {},
  }) {
    return _request('POST', path, token, body: body, query: query);
  }

  Future<dynamic> _patch(String path, String token, {Object? body}) {
    return _request('PATCH', path, token, body: body);
  }

  Future<dynamic> _put(String path, String token, {Object? body}) {
    return _request('PUT', path, token, body: body);
  }

  Future<dynamic> _graphql(
    String token, {
    required String query,
    required Map<String, Object?> variables,
  }) async {
    final body = await _post(
      '/graphql',
      token,
      body: {'query': query, 'variables': variables},
    );
    if (body case {'errors': final List<dynamic> errors}) {
      throw GitHubApiException(
        GitHubApiErrorKind.validation,
        errors.isEmpty ? 'GitHub GraphQL request failed.' : errors.toString(),
      );
    }
    return body;
  }

  Future<dynamic> _request(
    String method,
    String path,
    String token, {
    Object? body,
    Map<String, String> query = const {},
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final http.Response response;
    final headers = {
      'Accept': 'application/vnd.github+json',
      'Authorization': 'Bearer $token',
      'X-GitHub-Api-Version': '2022-11-28',
      if (body != null) 'Content-Type': 'application/json',
    };
    final encodedBody = body == null ? null : jsonEncode(body);
    try {
      response = switch (method) {
        'GET' => await _client.get(uri, headers: headers),
        'POST' => await _client.post(
          uri,
          headers: headers,
          body: encodedBody,
        ),
        'PATCH' => await _client.patch(
          uri,
          headers: headers,
          body: encodedBody,
        ),
        'PUT' => await _client.put(uri, headers: headers, body: encodedBody),
        _ => throw StateError('Unsupported HTTP method $method'),
      };
    } on http.ClientException catch (e) {
      throw GitHubApiException(GitHubApiErrorKind.network, e.message);
    } on SocketException catch (e) {
      throw GitHubApiException(GitHubApiErrorKind.network, e.message);
    }
    return _decodeResponse(response);
  }

  dynamic _decodeResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.trim().isEmpty) return null;
      return jsonDecode(response.body);
    }
    final message = _messageOf(response);
    switch (response.statusCode) {
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
      case 405:
        throw GitHubApiException(GitHubApiErrorKind.mergeBlocked, message);
      case 409:
        throw GitHubApiException(GitHubApiErrorKind.conflict, message);
      case 422:
        throw GitHubApiException(GitHubApiErrorKind.validation, message);
      default:
        throw GitHubApiException(
          GitHubApiErrorKind.network,
          'GitHub API returned ${response.statusCode}.',
        );
    }
  }

  String _messageOf(http.Response response) {
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return decoded['message'] as String? ??
          'GitHub API returned ${response.statusCode}.';
    } on Object {
      return 'GitHub API returned ${response.statusCode}.';
    }
  }
}
