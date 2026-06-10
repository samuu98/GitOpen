/// Derives browser URLs from a git remote URL so the UI can offer
/// "Open on GitHub/GitLab/Bitbucket" actions.
///
/// Pure functions — no I/O — so the host-specific path quirks are unit
/// testable. Unknown self-hosted forges fall back to GitHub-style paths,
/// which GitLab CE also accepts via its legacy routes.
library;

/// Browser destination derived from a remote. `null` when the remote URL is
/// not web-mappable (e.g. a local filesystem path).
class RemoteWebUrl {
  /// Repository home page, e.g. `https://github.com/user/repo`.
  final String base;

  final _Forge _forge;

  const RemoteWebUrl._(this.base, this._forge);

  /// Parses https/ssh/scp-style remote URLs:
  /// - `https://host/user/repo(.git)`
  /// - `ssh://git@host(:port)/user/repo(.git)`
  /// - `git@host:user/repo(.git)`
  static RemoteWebUrl? parse(String remoteUrl) {
    final url = remoteUrl.trim();
    if (url.isEmpty) return null;

    String? host;
    String? path;

    final https = RegExp(r'^https?://(?:[^@/]+@)?([^/:]+)(?::\d+)?/(.+)$')
        .firstMatch(url);
    final ssh =
        RegExp(r'^ssh://(?:[^@/]+@)?([^/:]+)(?::\d+)?/(.+)$').firstMatch(url);
    final scp = RegExp(r'^(?:[^@/]+@)([^/:]+):(?!\d+/)(.+)$').firstMatch(url);

    final m = https ?? ssh ?? scp;
    if (m == null) return null;
    host = m.group(1)!;
    path = m.group(2)!;

    path = path.replaceAll(RegExp(r'\.git/?$'), '');
    path = path.replaceAll(RegExp(r'/+$'), '');
    if (path.isEmpty) return null;

    final forge = switch (host.toLowerCase()) {
      'github.com' => _Forge.github,
      'bitbucket.org' => _Forge.bitbucket,
      final h when h.contains('gitlab') => _Forge.gitlab,
      final h when h.contains('dev.azure.com') => _Forge.azure,
      _ => _Forge.github, // sensible default for self-hosted forges
    };
    return RemoteWebUrl._('https://$host/$path', forge);
  }

  /// Web page for a single commit.
  String commit(String sha) => switch (_forge) {
        _Forge.github => '$base/commit/$sha',
        _Forge.gitlab => '$base/-/commit/$sha',
        _Forge.bitbucket => '$base/commits/$sha',
        _Forge.azure => '$base/commit/$sha',
      };

  /// Web page for a branch tree.
  String branch(String name) {
    final encoded = Uri.encodeComponent(name).replaceAll('%2F', '/');
    return switch (_forge) {
      _Forge.github => '$base/tree/$encoded',
      _Forge.gitlab => '$base/-/tree/$encoded',
      _Forge.bitbucket => '$base/branch/$encoded',
      _Forge.azure => '$base?version=GB$encoded',
    };
  }
}

enum _Forge { github, gitlab, bitbucket, azure }
