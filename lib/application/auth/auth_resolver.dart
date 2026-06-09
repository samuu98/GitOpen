import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_profile_store.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// Reads the configured URL of a repo's remote, or null when the remote does
/// not exist. Implemented over the git CLI in infrastructure; injected so the
/// resolver itself never spawns processes.
// ignore: one_member_abstracts
abstract interface class RemoteUrlReader {
  Future<String?> remoteUrl(RepoLocation repo, String remote);
}

/// Resolves which credential a git operation should use for a given repo.
///
/// Priority:
///   1. Explicit per-repo binding (`repoId → profileId`) — what the user
///      picked in the account-switcher.
///   2. Single saved profile for the remote host — implicit default.
///   3. None (caller falls back to system credential helper or prompts).
class AuthResolver {
  AuthResolver(
    this._store, {
    required RemoteUrlReader remoteUrl,
    String? Function(String repoId)? bindingLookup,
    LoggerPort? log,
  })  : _remoteUrl = remoteUrl,
        _bindingLookup = bindingLookup ?? ((_) => null),
        _log = log;
  final AuthProfileStore _store;
  final RemoteUrlReader _remoteUrl;
  final String? Function(String repoId) _bindingLookup;
  final LoggerPort? _log;

  /// Returns the resolved profile (with its `AuthSpec`) for a repo, or null
  /// if no candidate can be picked unambiguously.
  Future<AuthProfile?> resolveForRepo(
    RepoLocation repo, {
    String remote = 'origin',
  }) async {
    final sw = Stopwatch()..start();
    // 1. Per-repo binding wins.
    final boundId = _bindingLookup(repo.id.value);
    _log?.d('authResolver: bindingLookup=$boundId '
        '(${sw.elapsedMilliseconds}ms)');
    if (boundId != null) {
      final bound = await _store.get(boundId);
      _log?.d('authResolver: store.get done in ${sw.elapsedMilliseconds}ms '
          '(found=${bound != null})');
      if (bound != null) return bound;
    }

    // 2. Implicit single-profile-per-host fallback.
    final host = await hostFromRepo(repo, remote);
    _log?.d('authResolver: host="$host" (${sw.elapsedMilliseconds}ms)');
    if (host == null) return null;
    final candidates = await _store.forHost(host);
    _log?.d('authResolver: store.forHost done in '
        '${sw.elapsedMilliseconds}ms (candidates=${candidates.length})');
    if (candidates.length == 1) return candidates.first;
    // Multiple profiles & no binding → ambiguous; let the caller prompt.
    return null;
  }

  /// Convenience: just the host extracted from [remote]'s URL.
  Future<String?> hostFromRepo(
    RepoLocation repo,
    String remote,
  ) async {
    final url = await _remoteUrl.remoteUrl(repo, remote);
    if (url == null) return null;
    final https = RegExp('^https?://([^/]+)').firstMatch(url);
    if (https != null) return https.group(1);
    final ssh = RegExp('^git@([^:]+):').firstMatch(url);
    if (ssh != null) return ssh.group(1);
    return null;
  }
}
