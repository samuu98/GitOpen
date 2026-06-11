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
      expect(bad.state, CheckState.failure);
      expect(wip.state, CheckState.pending);
    });
  });
}
