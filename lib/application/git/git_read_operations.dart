import '../../domain/commits/commit_info.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/diff/diff_result.dart';
import '../../domain/diff/diff_spec.dart';
import '../../domain/files/file_tree_entry.dart';
import '../../domain/refs/branch.dart';
import '../../domain/refs/remote.dart';
import '../../domain/refs/stash.dart';
import '../../domain/refs/tag.dart';
import '../../domain/repositories/repo_location.dart';
import '../../domain/status/repo_status.dart';

class CommitQuery {
  final int? skip;
  final int? take;
  final String? refSpec;
  const CommitQuery({this.skip, this.take, this.refSpec});
}

abstract interface class GitReadOperations {
  Future<RepoStatus> getStatus(RepoLocation repo);
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query);
  Future<List<Branch>> getBranches(RepoLocation repo);
  Future<List<Tag>> getTags(RepoLocation repo);
  Future<List<Remote>> getRemotes(RepoLocation repo);
  Future<List<Stash>> getStashes(RepoLocation repo);
  Future<DiffResult> getDiff(RepoLocation repo, DiffSpec spec);
  Future<List<FileTreeEntry>> getFileTree(
      RepoLocation repo, CommitSha sha, String path);
}
