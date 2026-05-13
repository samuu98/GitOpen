import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gitopen/infrastructure/updates/github_release_updater.dart';

http.Response _jsonResponse(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

GitHubReleaseUpdater _makeUpdater(http.Client client) =>
    GitHubReleaseUpdater(owner: 'test-owner', repo: 'test-repo', client: client);

void main() {
  group('GitHubReleaseUpdater.checkForUpdates', () {
    test('returns version string when remote is newer', () async {
      final client = MockClient((_) async => _jsonResponse({'tag_name': 'v1.2.0'}));
      final updater = _makeUpdater(client);
      expect(await updater.checkForUpdates('1.1.0'), '1.2.0');
    });

    test('returns null when remote is same version', () async {
      final client = MockClient((_) async => _jsonResponse({'tag_name': 'v1.1.0'}));
      final updater = _makeUpdater(client);
      expect(await updater.checkForUpdates('1.1.0'), isNull);
    });

    test('returns null when remote is older', () async {
      final client = MockClient((_) async => _jsonResponse({'tag_name': 'v1.0.0'}));
      final updater = _makeUpdater(client);
      expect(await updater.checkForUpdates('1.1.0'), isNull);
    });

    test('returns null on non-200 response', () async {
      final client = MockClient((_) async => _jsonResponse({}, status: 404));
      final updater = _makeUpdater(client);
      expect(await updater.checkForUpdates('1.0.0'), isNull);
    });

    test('returns null when tag_name is absent', () async {
      final client = MockClient((_) async => _jsonResponse({'name': 'no tag here'}));
      final updater = _makeUpdater(client);
      expect(await updater.checkForUpdates('1.0.0'), isNull);
    });

    test('handles tag without v-prefix', () async {
      final client = MockClient((_) async => _jsonResponse({'tag_name': '2.0.0'}));
      final updater = _makeUpdater(client);
      expect(await updater.checkForUpdates('1.9.9'), '2.0.0');
    });
  });
}
