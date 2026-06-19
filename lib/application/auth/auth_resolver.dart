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

/// Reads the effective git `user.email` for a repo (local overrides global),
/// or null when unset. Implemented over GitIdentityService in infrastructure;
/// injected so the resolver itself never spawns processes.
// ignore: one_member_abstracts
abstract interface class RepoIdentityReader {
  Future<String?> effectiveEmail(RepoLocation repo);
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
    RepoIdentityReader? identity,
    LoggerPort? log,
  }) : _remoteUrl = remoteUrl,
       _bindingLookup = bindingLookup ?? ((_) => null),
       _identity = identity,
       _log = log;
  final AuthProfileStore _store;
  final RemoteUrlReader _remoteUrl;
  final String? Function(String repoId) _bindingLookup;
  final RepoIdentityReader? _identity;
  final LoggerPort? _log;

  // Cache the two slow git reads (each spawns a subprocess) keyed by repo so
  // repeated network ops skip them. These are stable git *facts* — not the
  // resolved credential — so account/profile changes need no invalidation; only
  // a remote-url or repo-email change does (see [clearCache]).
  final Map<String, String?> _remoteUrlCache = {};
  final Map<String, String?> _emailCache = {};

  /// Returns the resolved profile (with its `AuthSpec`) for a repo, or null
  /// if no candidate can be picked unambiguously.
  Future<AuthProfile?> resolveForRepo(
    RepoLocation repo, {
    String remote = 'origin',
  }) async {
    final sw = Stopwatch()..start();
    // 1. Per-repo binding wins.
    final boundId = _bindingLookup(repo.id.value);
    _log?.d(
      'authResolver: bindingLookup=$boundId '
      '(${sw.elapsedMilliseconds}ms)',
    );
    if (boundId != null) {
      final bound = await _store.get(boundId);
      _log?.d(
        'authResolver: store.get done in ${sw.elapsedMilliseconds}ms '
        '(found=${bound != null})',
      );
      if (bound != null) return bound;
    }

    // 2. Resolve the host; everything below is scoped to it.
    final host = await hostFromRepo(repo, remote);
    _log?.d('authResolver: host="$host" (${sw.elapsedMilliseconds}ms)');
    if (host == null) return null;
    final candidates = await _store.forHost(host);
    _log?.d(
      'authResolver: store.forHost done in '
      '${sw.elapsedMilliseconds}ms (candidates=${candidates.length})',
    );

    // 3. Identity (email) match — host-scoped. The repo's effective git
    // user.email (set per-folder via .gitconfig) selects the owning account.
    // Only matters when >1 candidate shares the host; otherwise the email read
    // (a git subprocess) can't change the result, so skip it.
    final identity = _identity;
    if (identity != null && candidates.length > 1) {
      final email = (await _cachedEmail(repo, identity))?.trim().toLowerCase();
      _log?.d(
        'authResolver: effectiveEmail="$email" '
        '(${sw.elapsedMilliseconds}ms)',
      );
      if (email != null && email.isNotEmpty) {
        final matches = candidates
            .where((p) => p.emails.contains(email))
            .toList(growable: false);
        if (matches.length == 1) return matches.first;
      }
    }

    // 4. Implicit single-profile-per-host fallback.
    if (candidates.length == 1) return candidates.first;
    // 5. Multiple profiles & no match → ambiguous; let the caller prompt.
    return null;
  }

  /// Convenience: just the host extracted from [remote]'s URL.
  Future<String?> hostFromRepo(
    RepoLocation repo,
    String remote,
  ) async {
    final url = await _cachedRemoteUrl(repo, remote);
    if (url == null) return null;
    final https = RegExp('^https?://([^/]+)').firstMatch(url);
    if (https != null) return https.group(1);
    final ssh = RegExp('^git@([^:]+):').firstMatch(url);
    if (ssh != null) return ssh.group(1);
    return null;
  }

  Future<String?> _cachedRemoteUrl(RepoLocation repo, String remote) async {
    final key = '${repo.id.value}|$remote';
    if (_remoteUrlCache.containsKey(key)) return _remoteUrlCache[key];
    final url = await _remoteUrl.remoteUrl(repo, remote);
    _remoteUrlCache[key] = url;
    return url;
  }

  Future<String?> _cachedEmail(
    RepoLocation repo,
    RepoIdentityReader identity,
  ) async {
    final key = repo.id.value;
    if (_emailCache.containsKey(key)) return _emailCache[key];
    final email = await identity.effectiveEmail(repo);
    _emailCache[key] = email;
    return email;
  }

  /// Drops the cached git facts (remote url + email) for [repoId], or for all
  /// repos when null. Call after a remote-url or repo-identity change.
  void clearCache([String? repoId]) {
    if (repoId == null) {
      _remoteUrlCache.clear();
      _emailCache.clear();
      return;
    }
    _remoteUrlCache.removeWhere((k, _) => k.startsWith('$repoId|'));
    _emailCache.remove(repoId);
  }
}
