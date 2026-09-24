import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// Preflight and guarded stash application shared by every stash entry point.
abstract interface class StashSafetyOperations {
  Future<GitResult<List<String>>> overlap(RepoLocation repo, int index);

  Future<GitResult<StashRestoreResult>> applyPreservingLocal(
    RepoLocation repo,
    int index, {
    required bool pop,
  });
}

final class StashRestoreResult {
  const StashRestoreResult({this.hasConflict = false, this.localStash});

  final bool hasConflict;
  final String? localStash;
}
