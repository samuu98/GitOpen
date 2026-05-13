import '../../domain/repositories/repo_location.dart';
import 'git_process_runner.dart';

/// Reads and writes the per-repo `user.name` / `user.email` config.
class GitIdentityService {
  final GitProcessRunner _runner;
  GitIdentityService({GitProcessRunner? runner})
      : _runner = runner ?? GitProcessRunner();

  /// Returns the local (per-repo) identity, or null for either field if
  /// it has not been set in the repo's own config.
  Future<({String? name, String? email})> readLocal(RepoLocation repo) async {
    final name = await _readKey(repo, 'user.name');
    final email = await _readKey(repo, 'user.email');
    return (name: name, email: email);
  }

  /// Returns the effective identity git would use for a commit in this repo:
  /// local overrides global, global overrides nothing.
  Future<({String? name, String? email})> readEffective(
      RepoLocation repo) async {
    final name = await _readKey(repo, 'user.name', global: false) ??
        await _readKey(repo, 'user.name', global: true);
    final email = await _readKey(repo, 'user.email', global: false) ??
        await _readKey(repo, 'user.email', global: true);
    return (name: name, email: email);
  }

  Future<void> setLocal(
      RepoLocation repo, String name, String email) async {
    await _runner.run(repo.path, ['config', '--local', 'user.name', name]);
    await _runner.run(repo.path, ['config', '--local', 'user.email', email]);
  }

  Future<String?> _readKey(RepoLocation repo, String key,
      {bool global = false}) async {
    try {
      final out = await _runner.run(
        repo.path,
        ['config', if (global) '--global' else '--local', '--get', key],
      );
      final trimmed = out.trim();
      return trimmed.isEmpty ? null : trimmed;
    } on GitProcessException {
      return null;
    }
  }
}
