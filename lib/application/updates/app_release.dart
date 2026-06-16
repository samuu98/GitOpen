import 'package:equatable/equatable.dart';

/// The host platform an installer asset targets.
enum InstallerPlatform { windows, linux, other }

/// A downloadable file attached to a GitHub release.
class ReleaseAsset extends Equatable {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;

  @override
  List<Object?> get props => [name, downloadUrl, sizeBytes];
}

/// A GitHub release: its version (tag without the `v`) and its assets.
class AppRelease extends Equatable {
  const AppRelease({required this.version, required this.assets});

  final String version;
  final List<ReleaseAsset> assets;

  @override
  List<Object?> get props => [version, assets];
}

/// Picks the installer asset for [platform]: the first `.exe` on Windows, the
/// first `.deb` on Linux. Returns null when no matching asset exists or the
/// platform is unsupported — callers then fall back to the release page.
ReleaseAsset? selectInstallerAsset(
  List<ReleaseAsset> assets,
  InstallerPlatform platform,
) {
  final ext = switch (platform) {
    InstallerPlatform.windows => '.exe',
    InstallerPlatform.linux => '.deb',
    InstallerPlatform.other => null,
  };
  if (ext == null) return null;
  for (final asset in assets) {
    if (asset.name.toLowerCase().endsWith(ext)) return asset;
  }
  return null;
}

/// Command-line args that make the platform installer run without a wizard.
/// Windows → Inno Setup silent flags. Linux installs via `dpkg` (see the
/// updater), so there are no installer args there.
List<String> installerLaunchArgs(InstallerPlatform platform) {
  return switch (platform) {
    InstallerPlatform.windows => const [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
    ],
    InstallerPlatform.linux || InstallerPlatform.other => const [],
  };
}

/// A `sh -c` script that relaunches GitOpen on Linux once the current process
/// (pid [appPid]) has exited, so the GApplication single-instance name is free
/// before the new instance starts. [exePath] is the freshly installed binary.
String linuxRelaunchScript(int appPid, String exePath) =>
    'while kill -0 $appPid 2>/dev/null; do sleep 0.1; done; exec "$exePath"';
