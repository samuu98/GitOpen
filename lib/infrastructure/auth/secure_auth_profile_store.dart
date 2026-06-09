import 'dart:convert';
import 'dart:math';

import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_profile_store.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/infrastructure/auth/dpapi_storage.dart';
import 'package:gitopen/infrastructure/logging/app_logger.dart';

/// DPAPI-backed implementation of [AuthProfileStore].
///
/// Storage layout:
///   `gitopen:auth:profile:<id>`       — JSON `{host, username, spec}`
///   `gitopen:auth:profile_index`      — JSON array of profile ids
///   `gitopen:auth:migrated_v1`        — sentinel ("ok"), marks old → new
///                                       migration as done
///
/// Migration: on first access, any entries from the previous host-keyed
/// scheme (`gitopen:auth:<host>` + `gitopen:auth:__index__`) are wrapped
/// into profiles.  Old keys are left in place to avoid data loss in case
/// of a roll-back.
class SecureAuthProfileStore implements AuthProfileStore {

  SecureAuthProfileStore({DpapiStorage? storage})
      : _storage = storage ?? DpapiStorage.instance;
  static const _profilePrefix = 'gitopen:auth:profile:';
  static const _profileIndexKey = 'gitopen:auth:profile_index';
  static const _migrationMarker = 'gitopen:auth:migrated_v1';

  // Legacy keys (previous CredentialsStore implementation).
  static const _legacyPrefix = 'gitopen:auth:';
  static const _legacyIndexKey = '${_legacyPrefix}__index__';

  final DpapiStorage _storage;
  bool _migrated = false;

  // ---------------------------------------------------------------------------
  // AuthProfileStore interface
  // ---------------------------------------------------------------------------

  @override
  Future<List<AuthProfile>> list() async {
    await _ensureMigrated();
    final ids = await _readIndex();
    final profiles = <AuthProfile>[];
    for (final id in ids) {
      final p = await _readProfile(id);
      if (p != null) profiles.add(p);
    }
    return profiles;
  }

  @override
  Future<AuthProfile?> get(String id) async {
    await _ensureMigrated();
    return _readProfile(id);
  }

  @override
  Future<List<AuthProfile>> forHost(String host) async {
    final sw = Stopwatch()..start();
    appLog.d('authStore.forHost("$host") start');
    final all = await list();
    final filtered = all.where((p) => p.host == host).toList(growable: false);
    appLog.d('authStore.forHost("$host") done in ${sw.elapsedMilliseconds}ms '
        '(total=${all.length}, matching=${filtered.length})');
    return filtered;
  }

  @override
  Future<AuthProfile> upsert({
    required String host,
    required String username,
    required AuthSpec spec,
    String? id,
  }) async {
    await _ensureMigrated();
    final effectiveId = id ?? _generateId();
    final profile = AuthProfile(
      id: effectiveId,
      host: host,
      username: username,
      spec: spec,
    );
    await _storage.write(_profileKey(effectiveId), _encode(profile));
    await _indexAdd(effectiveId);
    return profile;
  }

  @override
  Future<void> delete(String id) async {
    await _ensureMigrated();
    await _storage.delete(_profileKey(id));
    await _indexRemove(id);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  String _profileKey(String id) => '$_profilePrefix$id';

  Future<AuthProfile?> _readProfile(String id) async {
    final raw = await _storage.read(_profileKey(id));
    if (raw == null) return null;
    try {
      return _decode(id, raw);
    } on Object catch (_) {
      return null;
    }
  }

  Future<List<String>> _readIndex() async {
    final raw = await _storage.read(_profileIndexKey);
    if (raw == null) return <String>[];
    return (jsonDecode(raw) as List<dynamic>).cast<String>();
  }

  Future<void> _writeIndex(List<String> ids) async {
    await _storage.write(_profileIndexKey, jsonEncode(ids));
  }

  Future<void> _indexAdd(String id) async {
    final ids = await _readIndex();
    if (!ids.contains(id)) {
      ids.add(id);
      await _writeIndex(ids);
    }
  }

  Future<void> _indexRemove(String id) async {
    final ids = await _readIndex();
    if (ids.remove(id)) await _writeIndex(ids);
  }

  /// Idempotent one-shot migration from the legacy host-keyed scheme.
  ///
  /// IMPORTANT: [_migrated] is set to `true` BEFORE running [_migrateLegacy].
  /// The migration writes through [upsert], and [upsert] itself calls
  /// [_ensureMigrated] — without flipping the flag first, the recursive
  /// re-entry would observe `_migrated == false` and the empty marker,
  /// then re-run the migration, then call upsert again, etc. forever.
  /// The recursion never stops to read from a real I/O source after the
  /// in-memory file cache warms, so it loops as a pure microtask burst —
  /// which silently starves every `Timer` and `Process` callback in the
  /// isolate, presenting as a total UI freeze with no error.
  Future<void> _ensureMigrated() async {
    if (_migrated) return;
    final sw = Stopwatch()..start();
    appLog.d('authStore.ensureMigrated start');
    final marker = await _storage.read(_migrationMarker);
    appLog.d('authStore.ensureMigrated marker="$marker" '
        '(${sw.elapsedMilliseconds}ms)');
    if (marker == 'ok') {
      _migrated = true;
      return;
    }
    // Flip the flag BEFORE migration so reentry from upsert short-circuits.
    _migrated = true;
    await _migrateLegacy();
    appLog.d('authStore.migrateLegacy done (${sw.elapsedMilliseconds}ms)');
    await _storage.write(_migrationMarker, 'ok');
    appLog.d('authStore.ensureMigrated done '
        '(${sw.elapsedMilliseconds}ms)');
  }

  Future<void> _migrateLegacy() async {
    final legacyIndexRaw = await _storage.read(_legacyIndexKey);
    if (legacyIndexRaw == null) return;
    final hosts = (jsonDecode(legacyIndexRaw) as List<dynamic>).cast<String>();
    for (final host in hosts) {
      final blob = await _storage.read('$_legacyPrefix$host');
      if (blob == null) continue;
      try {
        final spec = _decodeLegacySpec(blob);
        if (spec == null) continue;
        await upsert(
          host: host,
          username: _usernameFromSpec(spec),
          spec: spec,
        );
      } on Object catch (_) {
        // Skip unparseable entries — they remain in place under their old key.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Encode / decode
  // ---------------------------------------------------------------------------

  String _encode(AuthProfile p) {
    return jsonEncode({
      'host': p.host,
      'username': p.username,
      'spec': _encodeSpec(p.spec),
    });
  }

  AuthProfile _decode(String id, String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return AuthProfile(
      id: id,
      host: m['host'] as String,
      username: m['username'] as String,
      spec: _decodeSpec(m['spec'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> _encodeSpec(AuthSpec spec) {
    return switch (spec) {
      AuthHttpsPat() => {
          'kind': 'pat',
          'username': spec.username,
          'token': spec.token,
        },
      AuthHttpsBasic() => {
          'kind': 'basic',
          'username': spec.username,
          'password': spec.password,
        },
      AuthSsh() => {
          'kind': 'ssh',
          'keyPath': spec.privateKeyPath,
          'passphrase': spec.passphrase,
        },
      AuthGitHubOauth() => {'kind': 'github', 'token': spec.accessToken},
      AuthSystemDefault() => {'kind': 'system'},
    };
  }

  AuthSpec _decodeSpec(Map<String, dynamic> m) {
    switch (m['kind']) {
      case 'pat':
        return AuthHttpsPat(
          username: m['username'] as String,
          token: m['token'] as String,
        );
      case 'basic':
        return AuthHttpsBasic(
          username: m['username'] as String,
          password: m['password'] as String,
        );
      case 'ssh':
        return AuthSsh(
          privateKeyPath: m['keyPath'] as String,
          passphrase: m['passphrase'] as String?,
        );
      case 'github':
        return AuthGitHubOauth(m['token'] as String);
      case 'system':
        return const AuthSystemDefault();
      default:
        throw FormatException('Unknown auth kind: ${m['kind']}');
    }
  }

  /// Legacy decoder: the previous store wrote a top-level spec JSON object
  /// (no host/username wrapper).  Same shape as our [_decodeSpec] inner map.
  AuthSpec? _decodeLegacySpec(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return _decodeSpec(m);
    } on Object catch (_) {
      return null;
    }
  }

  /// Best-effort guess of a human label when migrating a legacy entry that
  /// had no username field.  Real usernames are filled in later by the auth
  /// dialog after a successful sign-in.
  String _usernameFromSpec(AuthSpec spec) {
    return switch (spec) {
      AuthHttpsPat(:final username) => username,
      AuthHttpsBasic(:final username) => username,
      AuthSsh() => '(ssh key)',
      AuthGitHubOauth() => '(unknown)',
      AuthSystemDefault() => '(system)',
    };
  }

  // ---------------------------------------------------------------------------
  // Id generation
  // ---------------------------------------------------------------------------

  static final _rng = Random.secure();

  /// Compact, URL-safe random id (16 hex chars = 64 bits of entropy).
  /// Collision risk for the few-profile scenarios we care about is negligible.
  String _generateId() {
    final bytes = List<int>.generate(8, (_) => _rng.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
