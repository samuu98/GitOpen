import 'dart:convert';
import 'dart:io';

import 'package:gitopen/application/updates/app_release.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Checks GitHub Releases for a newer version of GitOpen and can download +
/// launch the platform installer in-app, so the user never has to open the
/// browser to update.
class GitHubReleaseUpdater {
  GitHubReleaseUpdater({
    this.owner = 'zN3utr4l',
    this.repo = 'GitOpen',
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String owner;
  final String repo;
  final http.Client _client;

  /// Fetches the latest GitHub release (version + assets). Returns null on a
  /// non-200 response, a missing tag, or a parse failure.
  Future<AppRelease?> fetchLatestRelease() async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases/latest',
    );
    final response = await _client.get(
      uri,
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = body['tag_name'] as String?;
    if (tag == null) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;

    final rawAssets = (body['assets'] as List<dynamic>?) ?? const [];
    final assets = <ReleaseAsset>[];
    for (final raw in rawAssets) {
      if (raw is! Map<String, dynamic>) continue;
      final name = raw['name'] as String?;
      final url = raw['browser_download_url'] as String?;
      if (name == null || url == null) continue;
      assets.add(
        ReleaseAsset(
          name: name,
          downloadUrl: url,
          sizeBytes: (raw['size'] as int?) ?? 0,
        ),
      );
    }
    return AppRelease(version: version, assets: assets);
  }

  /// Returns the latest release when it is newer than [currentVersion], or
  /// null when the app is up-to-date / the check fails.
  Future<AppRelease?> checkForUpdate(String currentVersion) async {
    final release = await fetchLatestRelease();
    if (release == null) return null;
    return _isNewer(release.version, currentVersion) ? release : null;
  }

  /// Backwards-compatible shim: the newer version string, or null.
  Future<String?> checkForUpdates(String currentVersion) async =>
      (await checkForUpdate(currentVersion))?.version;

  /// The installer asset for the current OS, or null (→ fall back to the
  /// release page).
  ReleaseAsset? installerAssetFor(AppRelease release) =>
      selectInstallerAsset(release.assets, _currentPlatform());

  /// Downloads [asset] to the temp directory reporting 0..1 [onProgress], then
  /// launches it: on Windows runs the installer; on Linux opens the `.deb`
  /// with the system handler. The caller should prompt the user to quit so
  /// the installer can replace files.
  Future<void> downloadAndInstall(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final file = await _download(asset, onProgress);
    await _launch(file);
  }

  Future<File> _download(
    ReleaseAsset asset,
    void Function(double)? onProgress,
  ) async {
    final response = await _client.send(
      http.Request('GET', Uri.parse(asset.downloadUrl)),
    );
    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }
    final total = response.contentLength ?? asset.sizeBytes;
    final file = File(p.join(Directory.systemTemp.path, asset.name));
    final sink = file.openWrite();
    try {
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null && total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
    } finally {
      await sink.close();
    }
    return file;
  }

  Future<void> _launch(File file) async {
    if (Platform.isWindows) {
      await Process.start(file.path, const [], mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      await Process.start(
        'xdg-open',
        [file.path],
        mode: ProcessStartMode.detached,
      );
    } else {
      await launchUrl(Uri.file(file.path));
    }
  }

  InstallerPlatform _currentPlatform() {
    if (Platform.isWindows) return InstallerPlatform.windows;
    if (Platform.isLinux) return InstallerPlatform.linux;
    return InstallerPlatform.other;
  }

  /// Opens the GitHub Releases page in the default browser (fallback when no
  /// installer asset matches the platform).
  Future<void> openReleasesPage() async {
    final uri = Uri.parse('https://github.com/$owner/$repo/releases/latest');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// True when [candidate] is strictly newer than [current] (semver MAJOR.
  /// MINOR.PATCH, compared numerically).
  bool _isNewer(String candidate, String current) {
    final c = _parse(candidate);
    final v = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (c[i] > v[i]) return true;
      if (c[i] < v[i]) return false;
    }
    return false;
  }

  List<int> _parse(String version) {
    final parts = version.split('.');
    return List.generate(
      3,
      (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0,
    );
  }
}
