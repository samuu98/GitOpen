import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/github/github_api.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/infrastructure/github/github_rest_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const ({String owner, String repo}) _slug = (owner: 'o', repo: 'r');

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
    final runs = await _api(
      client,
    ).listWorkflowRuns(_slug, token: 'tok', branch: 'main');
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
    expect(summary.succeeded, 2);
    expect(summary.failed, 1);
    expect(summary.pending, 1);
  });

  group('pull request details and mutations', () {
    test('getPullRequest parses detail fields', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/repos/o/r/pulls/7');
        return http.Response(jsonEncode(_detailJson()), 200);
      });

      final detail = await _api(client).getPullRequest(
        _slug,
        7,
        token: 'tok',
      );

      expect(detail.number, 7);
      expect(detail.nodeId, 'PR_kwDOExample');
      expect(detail.title, 'Add thing');
      expect(detail.body, 'Body text');
      expect(detail.author, 'ada');
      expect(detail.state, 'open');
      expect(detail.isDraft, isTrue);
      expect(detail.mergeable, isTrue);
      expect(detail.mergeStateStatus, 'clean');
      expect(detail.baseRef, 'main');
      expect(detail.headRef, 'feat/x');
      expect(detail.headSha, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    });

    test('listPullRequestFiles parses file patches', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/repos/o/r/pulls/7/files');
        return http.Response(
          jsonEncode([
            {
              'filename': 'lib/app.dart',
              'status': 'modified',
              'additions': 2,
              'deletions': 1,
              'changes': 3,
              'patch': '@@ -1,2 +1,3 @@\n old\n+new\n same',
            },
          ]),
          200,
        );
      });

      final files = await _api(
        client,
      ).listPullRequestFiles(_slug, 7, token: 't');

      expect(files.single.filename, 'lib/app.dart');
      expect(files.single.patch, contains('+new'));
    });

    test('createPullRequest posts the expected body', () async {
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/repos/o/r/pulls');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_detailJson(number: 8)), 201);
      });

      final created = await _api(client).createPullRequest(
        _slug,
        const CreatePullRequestRequest(
          title: 'New PR',
          body: 'Ready',
          head: 'feat/x',
          base: 'main',
          draft: true,
        ),
        token: 'tok',
      );

      expect(body, {
        'title': 'New PR',
        'body': 'Ready',
        'head': 'feat/x',
        'base': 'main',
        'draft': true,
      });
      expect(created.number, 8);
    });

    test('mergePullRequest maps blocked merge responses', () async {
      final client = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/repos/o/r/pulls/7/merge');
        return http.Response(
          jsonEncode({'message': 'Pull Request is not mergeable'}),
          405,
        );
      });

      await expectLater(
        _api(client).mergePullRequest(
          _slug,
          7,
          const MergePullRequestRequest(
            method: PullRequestMergeMethod.squash,
          ),
          token: 'tok',
        ),
        throwsA(
          isA<GitHubApiException>().having(
            (e) => e.kind,
            'kind',
            GitHubApiErrorKind.mergeBlocked,
          ),
        ),
      );
    });
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
        isA<GitHubApiException>().having(
          (e) => e.kind,
          'kind',
          GitHubApiErrorKind.network,
        ),
      ),
    );
  });
}

Map<String, dynamic> _detailJson({int number = 7}) => {
  'node_id': 'PR_kwDOExample',
  'number': number,
  'title': 'Add thing',
  'body': 'Body text',
  'state': 'open',
  'draft': true,
  'mergeable': true,
  'mergeable_state': 'clean',
  'html_url': 'https://github.com/o/r/pull/$number',
  'created_at': '2026-06-11T09:00:00Z',
  'updated_at': '2026-06-11T10:00:00Z',
  'user': {'login': 'ada'},
  'base': {'ref': 'main'},
  'head': {'ref': 'feat/x', 'sha': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'},
};
