import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Checks GitHub Releases for a newer version of GitOpen.
///
/// Returns the latest version string if a newer release is found, or null
/// if the app is already up-to-date or the check fails.  Does not
/// auto-install — on "update available" the caller should offer
/// [openReleasesPage] so the user can download and install manually.
class GitHubReleaseUpdater {
  final String owner;
  final String repo;
  final http.Client _client;

  GitHubReleaseUpdater({
    this.owner = 's-porta',
    this.repo = 'gitopen',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Returns the latest release version string (e.g. `"1.2.0"`) when it is
  /// newer than [currentVersion], or `null` when the app is up-to-date.
  ///
  /// Throws on network / parse errors so callers can surface them to the user.
  Future<String?> checkForUpdates(String currentVersion) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases/latest',
    );
    final response = await _client.get(uri, headers: {
      'Accept': 'application/vnd.github+json',
    });

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = body['tag_name'] as String?;
    if (tag == null) return null;

    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    return _isNewer(latest, currentVersion) ? latest : null;
  }

  /// Opens the GitHub Releases page in the default browser.
  Future<void> openReleasesPage() async {
    final uri = Uri.parse('https://github.com/$owner/$repo/releases/latest');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Returns true when [candidate] is strictly newer than [current].
  /// Compares semver-style `MAJOR.MINOR.PATCH` components numerically.
  bool _isNewer(String candidate, String current) {
    final c = _parse(candidate);
    final v = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (c[i] > v[i]) return true;
      if (c[i] < v[i]) return false;
    }
    return false; // equal
  }

  List<int> _parse(String version) {
    final parts = version.split('.');
    return List.generate(3, (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
  }
}
