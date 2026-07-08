import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/infrastructure/git/credential_helper.dart';

String _basic(String user, String secret) =>
    base64.encode(utf8.encode('$user:$secret'));

void main() {
  group('CredentialHelper — host-scoped extraheader', () {
    test('PAT scopes the Authorization header to the remote host', () async {
      final h = await CredentialHelper.setup(
        const AuthHttpsPat(username: 'octocat', token: 'ghp_secret'),
        remoteUrl: 'https://github.com/Owner/repo.git',
      );
      final basic = _basic('octocat', 'ghp_secret');
      // Host-scoped key so git-lfs does NOT apply the header to the S3
      // storage host (github-cloud.s3.amazonaws.com), which rejects it (501).
      expect(
        h.extraArgs,
        containsAllInOrder(<String>[
          '-c',
          'http.https://github.com/.extraheader=Authorization: Basic $basic',
        ]),
      );
      // The unscoped global key must NOT be emitted — that is the leak.
      expect(
        h.extraArgs,
        isNot(contains('http.extraheader=Authorization: Basic $basic')),
      );
      // Still resets inherited credential helpers (e.g. GCM).
      expect(
        h.extraArgs,
        containsAllInOrder(<String>['-c', 'credential.helper=']),
      );
    });

    test('GitHub OAuth uses x-access-token and scopes to host', () async {
      final h = await CredentialHelper.setup(
        const AuthGitHubOauth('gho_token'),
        remoteUrl: 'https://github.com/o/r.git',
      );
      final basic = _basic('x-access-token', 'gho_token');
      expect(
        h.extraArgs,
        contains('http.https://github.com/.extraheader=Authorization: Basic $basic'),
      );
    });

    test('honours the actual scheme and host of the remote', () async {
      final h = await CredentialHelper.setup(
        const AuthHttpsBasic(username: 'u', password: 'p'),
        remoteUrl: 'https://gitlab.example.com:8443/group/proj.git',
      );
      final basic = _basic('u', 'p');
      expect(
        h.extraArgs,
        contains(
          'http.https://gitlab.example.com:8443/.extraheader=Authorization: Basic $basic',
        ),
      );
    });

    test('falls back to a global header when the remote URL is unknown',
        () async {
      final h = await CredentialHelper.setup(
        const AuthHttpsPat(username: 'u', token: 't'),
      );
      final basic = _basic('u', 't');
      // Without a URL we cannot scope; keep authenticating (global) rather
      // than silently failing auth.
      expect(
        h.extraArgs,
        contains('http.extraheader=Authorization: Basic $basic'),
      );
    });

    test('SSH is unaffected by remoteUrl (uses GIT_SSH_COMMAND)', () async {
      final h = await CredentialHelper.setup(
        const AuthSsh(privateKeyPath: '/home/u/.ssh/id_ed25519'),
        remoteUrl: 'https://github.com/o/r.git',
      );
      expect(h.extraArgs, isEmpty);
      expect(h.env['GIT_SSH_COMMAND'], contains('id_ed25519'));
    });
  });
}
