import 'package:gitopen/domain/blame/blame_line.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/files/file_tree_entry.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';

class CommitQuery {
  const CommitQuery({
    this.skip,
    this.take,
    this.refSpec,
    this.refs,
    this.grep,
    this.author,
    this.touchingContent,
  });
  final int? skip;
  final int? take;
  final String? refSpec;
  final List<String>? refs;

  /// Filter to commits whose message matches this pattern, case-insensitively
  /// (`git log --grep=<v> --regexp-ignore-case`).  Null disables the filter.
  final String? grep;

  /// Filter to commits authored by a matching author name/email
  /// (`git log --author=<v>`).  Null disables the filter.
  final String? author;

  /// Filter to commits that add or remove an occurrence of this string in any
  /// changed file — git's "pickaxe" search (`git log -S<v>`).  Null disables
  /// the filter.
  final String? touchingContent;
}

abstract interface class GitReadOperations {
  Future<RepoStatus> getStatus(RepoLocation repo);
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query);

  /// Returns the full commit message (subject + body) for a single sha.
  /// Bulk [getCommits] intentionally omits the body to keep the graph load
  /// linear in commit count; details views call this on demand.
  Future<String?> getCommitFullMessage(RepoLocation repo, CommitSha sha);

  /// Local branches only (`refs/heads`) — always fast.
  Future<List<Branch>> getLocalBranches(RepoLocation repo);

  /// Remote tracking branches (`refs/remotes`).  May time out on repos
  /// with very large unpruned remote ref sets — implementations are
  /// expected to return whatever partial list they got rather than hang.
  Future<List<Branch>> getRemoteBranches(RepoLocation repo);

  /// Convenience: locals + remotes concatenated.  Kept for callers that
  /// want the full list and are happy waiting for both.
  Future<List<Branch>> getBranches(RepoLocation repo);
  Future<List<Tag>> getTags(RepoLocation repo);
  Future<List<Remote>> getRemotes(RepoLocation repo);
  Future<List<Stash>> getStashes(RepoLocation repo);

  /// Submodules registered in the superproject (`git submodule status`).
  /// Empty output (no submodules) yields an empty list.
  Future<List<Submodule>> getSubmodules(RepoLocation repo);

  Future<DiffResult> getDiff(RepoLocation repo, DiffSpec spec);
  Future<List<FileTreeEntry>> getFileTree(
      RepoLocation repo, CommitSha sha, String path);

  /// Commits that touched [path], newest first, following renames
  /// (`git log --follow`).  [take] caps the number of commits returned
  /// (`--max-count`); null returns the full history.  The returned
  /// [CommitInfo]s carry the same fields as bulk [getCommits] (body omitted —
  /// fetch on demand via [getCommitFullMessage]).
  Future<List<CommitInfo>> getFileHistory(
    RepoLocation repo,
    String path, {
    int? take,
  });

  /// Per-line authorship for [path] (`git blame --porcelain`).  When [at] is
  /// given, blames the file as of that revision instead of the working tree.
  Future<List<BlameLine>> getBlame(
    RepoLocation repo,
    String path, {
    CommitSha? at,
  });
}
