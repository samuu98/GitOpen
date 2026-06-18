import 'dart:convert';
import 'dart:io';

import 'package:gitopen/application/updates/app_release.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Thrown when the update check cannot reach GitHub (non-200). Distinguishes a
/// failed check from "no newer version" so the UI never reports a failure as
/// "up to date".
class UpdateCheckException implements Exception {
  UpdateCheckException(this.statusCode);
  final int statusCode;

  @override
  String toString() => statusCode == 403
      ? 'GitHub rate limit reached (HTTP 403) — try again later, or sign in '
          'to GitHub in Settings so checks are authenticated.'
      : 'update check failed (HTTP $statusCode)';
}

/// Checks GitHub Releases for a newer version of GitOpen and can download +
/// launch the platform installer in-app, so the user never has to open the
/// browser to update.
class GitHubReleaseUpdater {
  GitHubReleaseUpdater({
    this.owner = 'zN3utr4l',
    this.repo = 'GitOpen',
    http.Client? client,
    Future<String?> Function()? token,
  })  : _client = client ?? http.Client(),
        _token = token;
  final String owner;
  final String repo;
  final http.Client _client;

  /// Resolves a GitHub token to authenticate the API call (5000 req/h instead
  /// of the shared 60/h unauthenticated per-IP limit — important on corporate
  /// NAT). Null/absent → unauthenticated.
  final Future<String?> Function()? _token;

  /// Fetches the latest GitHub release (version + assets). Returns null on a
  /// non-200 response, a missing tag, or a parse failure.
  Future<AppRelease?> fetchLatestRelease() async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases/latest',
    );
    final headers = {'Accept': 'application/vnd.github+json'};
    final token = await _token?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await _client.get(uri, headers: headers);
    // A non-200 (rate limit, offline, server error) is a CHECK FAILURE, not
    // "up to date" — throw so the UI reports it honestly instead of pretending
    // the app is current.
    if (response.statusCode != 200) {
      throw UpdateCheckException(response.statusCode);
    }

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
    await _install(file);
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

  /// Installs [file] without a wizard. Windows: runs the Inno installer
  /// silently (its `[Run]` step relaunches GitOpen). Linux: `pkexec dpkg -i`,
  /// then schedules a relaunch once this process exits. On failure, opens the
  /// package with the system handler and rethrows so the caller keeps the app
  /// open.
  Future<void> _install(File file) async {
    if (Platform.isWindows) {
      await Process.start(
        file.path,
        installerLaunchArgs(InstallerPlatform.windows),
        mode: ProcessStartMode.detached,
      );
      return;
    }
    if (Platform.isLinux) {
      ProcessResult result;
      try {
        result = await Process.run('pkexec', ['dpkg', '-i', file.path]);
      } on ProcessException {
        await Process.start(
          'xdg-open',
          [file.path],
          mode: ProcessStartMode.detached,
        );
        throw Exception('pkexec is unavailable; opened the package installer.');
      }
      if (result.exitCode != 0) {
        await Process.start(
          'xdg-open',
          [file.path],
          mode: ProcessStartMode.detached,
        );
        throw Exception(
          'Silent install failed (exit ${result.exitCode}); '
          'opened the package installer instead.',
        );
      }
      final script = linuxRelaunchScript(pid, Platform.resolvedExecutable);
      await Process.start(
        'sh',
        ['-c', script],
        mode: ProcessStartMode.detached,
      );
      return;
    }
    await launchUrl(Uri.file(file.path));
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
