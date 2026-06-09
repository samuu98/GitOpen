import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';

/// Persistent multi-account credential store.
///
/// Replaces the older host-keyed `CredentialsStore`: every entry is keyed by
/// a stable profile id, and any number of profiles may exist for the same
/// host.  Implementations are expected to migrate old single-credential
/// entries transparently on first access.
abstract interface class AuthProfileStore {
  /// All saved profiles.
  Future<List<AuthProfile>> list();

  /// Profile by id, or `null` if missing.
  Future<AuthProfile?> get(String id);

  /// All profiles for a given host.
  Future<List<AuthProfile>> forHost(String host);

  /// Create a new profile or overwrite the existing one with the same id.
  /// If [id] is null, a fresh id is generated and returned.
  Future<AuthProfile> upsert({
    required String host,
    required String username,
    required AuthSpec spec,
    String? id,
  });

  /// Delete the profile with the given id.  No-op if absent.
  Future<void> delete(String id);
}
