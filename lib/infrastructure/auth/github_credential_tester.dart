import 'dart:convert';

import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/credential_tester.dart';
import 'package:gitopen/application/github/github_api.dart' show githubTokenOf;
import 'package:http/http.dart' as http;

/// [CredentialTester] that validates a profile's token against the GitHub REST
/// API (`GET /user`). Unlike an anonymous `git ls-remote https://<host>` — which
/// fails with "repository not found" because the host root is not a repo and
/// never exercises the credential — this actually authenticates the token.
class GitHubApiCredentialTester implements CredentialTester {
  GitHubApiCredentialTester({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;

  @override
  Future<CredentialTestResult> test(AuthProfile profile) async {
    final token = githubTokenOf(profile.spec);
    if (token == null || token.isEmpty) {
      return (
        ok: false,
        message: 'This credential type has no API token to test '
            '(only PAT / GitHub OAuth can be verified).',
      );
    }
    // github.com → api.github.com; GitHub Enterprise → https://<host>/api/v3.
    final base = profile.host == 'github.com'
        ? 'https://api.github.com'
        : 'https://${profile.host}/api/v3';
    try {
      final r = await _client.get(
        Uri.parse('$base/user'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
      switch (r.statusCode) {
        case 200:
          final login = (jsonDecode(r.body) as Map<String, dynamic>)['login'];
          final loginStr = login is String ? login : '?';
          final mismatch =
              loginStr.toLowerCase() != profile.username.toLowerCase();
          return (
            ok: true,
            message: mismatch
                ? 'OK — token authenticates as "$loginStr", but this profile '
                    'is set to "${profile.username}". Update the username.'
                : 'OK — authenticated as "$loginStr" on ${profile.host}.',
          );
        case 401:
          return (ok: false, message: 'Invalid or expired token (401).');
        case 403:
          return (
            ok: false,
            message: 'Token rejected (403) — missing scope or rate limited.',
          );
        default:
          return (ok: false, message: 'GitHub returned HTTP ${r.statusCode}.');
      }
    } on Object catch (e) {
      return (ok: false, message: 'Could not reach ${profile.host}: $e');
    }
  }
}
