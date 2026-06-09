import 'dart:convert';

import 'package:http/http.dart' as http;

/// Looks up the authenticated GitHub user's login from an OAuth token, so the
/// UI does not perform HTTP calls itself.
class GitHubUserService {
  const GitHubUserService();

  /// `GET https://api.github.com/user` with [token]; returns the `login`, or
  /// `null` on any failure (the caller falls back to a sentinel label).
  Future<String?> fetchLogin(String token) async {
    try {
      final r = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
      if (r.statusCode == 200) {
        final m = jsonDecode(r.body) as Map<String, dynamic>;
        final login = m['login'];
        if (login is String && login.isNotEmpty) return login;
      }
    } on Object catch (_) {
      // fall through
    }
    return null;
  }
}
