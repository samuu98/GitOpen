import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/infrastructure/auth/github_credential_tester.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AuthProfile _pat({String host = 'github.com', String token = 'tok'}) =>
    AuthProfile(
      id: 'p1',
      host: host,
      username: 'octocat',
      spec: AuthHttpsPat(username: 'octocat', token: token),
    );

void main() {
  group('GitHubApiCredentialTester', () {
    test('valid token → ok, authenticated as the login', () async {
      Uri? hit;
      String? auth;
      final client = MockClient((request) async {
        hit = request.url;
        auth = request.headers['Authorization'];
        return http.Response(jsonEncode({'login': 'octocat'}), 200);
      });
      final tester = GitHubApiCredentialTester(client: client);

      final r = await tester.test(_pat(token: 'ghp_xyz'));

      expect(r.ok, isTrue);
      expect(r.message, contains('octocat'));
      expect(hit, Uri.parse('https://api.github.com/user'));
      expect(auth, 'Bearer ghp_xyz');
    });

    test('login differing from the saved username is flagged', () async {
      final client = MockClient(
        (request) async => http.Response(jsonEncode({'login': 'someone'}), 200),
      );
      final tester = GitHubApiCredentialTester(client: client);

      final r = await tester.test(_pat());

      expect(r.ok, isTrue);
      expect(r.message, contains('someone'));
      expect(r.message, contains('octocat'));
    });

    test('401 → not ok, invalid/expired message', () async {
      final client = MockClient(
        (request) async => http.Response('Bad credentials', 401),
      );
      final tester = GitHubApiCredentialTester(client: client);

      final r = await tester.test(_pat());

      expect(r.ok, isFalse);
      expect(r.message.toLowerCase(), contains('401'));
    });

    test('non-github host uses the GHE /api/v3 base', () async {
      Uri? hit;
      final client = MockClient((request) async {
        hit = request.url;
        return http.Response(jsonEncode({'login': 'u'}), 200);
      });
      final tester = GitHubApiCredentialTester(client: client);

      await tester.test(_pat(host: 'ghe.corp.local'));

      expect(hit, Uri.parse('https://ghe.corp.local/api/v3/user'));
    });

    test('credential with no API token reports it cannot be tested', () async {
      final client = MockClient((request) async => http.Response('', 200));
      final tester = GitHubApiCredentialTester(client: client);

      final r = await tester.test(
        const AuthProfile(
          id: 'p2',
          host: 'github.com',
          username: 'u',
          spec: AuthSsh(privateKeyPath: '/k'),
        ),
      );

      expect(r.ok, isFalse);
      expect(r.message.toLowerCase(), contains('token'));
    });

    test('network failure → not ok, graceful message', () async {
      final client = MockClient(
        (request) async => throw http.ClientException('down'),
      );
      final tester = GitHubApiCredentialTester(client: client);

      final r = await tester.test(_pat());

      expect(r.ok, isFalse);
      expect(r.message, isNotEmpty);
    });
  });
}
