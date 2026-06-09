import 'package:gitopen/application/auth/auth_resolver.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';

/// [RemoteUrlReader] over `git remote get-url`. Any failure (missing remote,
/// not a repo, git missing) resolves to null — the resolver treats that as
/// "no host".
class GitRemoteUrlReader implements RemoteUrlReader {
  GitRemoteUrlReader({GitProcessRunner? runner})
      : _runner = runner ?? GitProcessRunner();
  final GitProcessRunner _runner;

  @override
  Future<String?> remoteUrl(RepoLocation repo, String remote) async {
    try {
      final out =
          await _runner.run(repo.path, ['remote', 'get-url', remote]);
      final url = out.trim();
      return url.isEmpty ? null : url;
    } on Object {
      return null;
    }
  }
}
