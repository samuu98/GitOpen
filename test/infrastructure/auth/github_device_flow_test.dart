import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/auth/github_device_flow.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

DeviceCodeResponse _resp({
  Duration expiresIn = const Duration(milliseconds: 400),
}) =>
    DeviceCodeResponse(
      deviceCode: 'dev-1',
      userCode: 'ABCD-1234',
      verificationUri: 'https://github.com/login/device',
      expiresIn: expiresIn,
      interval: Duration.zero,
    );

void main() {
  group('GitHubDeviceFlow.requestDeviceCode', () {
    test('requests repo, read:org and user:email scopes', () async {
      String? sentScope;
      final client = MockClient((request) async {
        sentScope = request.bodyFields['scope'];
        return http.Response(
          jsonEncode({
            'device_code': 'dev-1',
            'user_code': 'ABCD-1234',
            'verification_uri': 'https://github.com/login/device',
            'expires_in': 900,
            'interval': 5,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final flow = GitHubDeviceFlow(clientId: 'cid', client: client);
      await flow.requestDeviceCode();
      expect(sentScope, 'repo read:org user:email');
    });
  });

  group('GitHubDeviceFlow.pollForToken robustness', () {
    test('a transient network failure does not abort the poll', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          throw http.ClientException('connection reset');
        }
        return http.Response(
          jsonEncode({'access_token': 'tok_ok'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final flow = GitHubDeviceFlow(clientId: 'cid', client: client);
      final token = await flow.pollForToken(_resp());
      expect(token, 'tok_ok');
      expect(calls, 2);
    });

    test('authorization_pending keeps polling until the token arrives',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls < 3) {
          return http.Response(
            jsonEncode({'error': 'authorization_pending'}),
            200,
          );
        }
        return http.Response(jsonEncode({'access_token': 'tok_ok'}), 200);
      });
      final flow = GitHubDeviceFlow(clientId: 'cid', client: client);
      final token = await flow.pollForToken(_resp());
      expect(token, 'tok_ok');
      expect(calls, 3);
    });

    test('a fatal provider error still aborts immediately', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'access_denied'}), 200);
      });
      final flow = GitHubDeviceFlow(clientId: 'cid', client: client);
      await expectLater(
        flow.pollForToken(_resp()),
        throwsA(isA<StateError>()),
      );
    });

    test('persistent network failure times out at the code expiry', () async {
      final client = MockClient((request) async {
        throw http.ClientException('still down');
      });
      final flow = GitHubDeviceFlow(clientId: 'cid', client: client);
      await expectLater(
        flow.pollForToken(_resp(expiresIn: const Duration(milliseconds: 150))),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
