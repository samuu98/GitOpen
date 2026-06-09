import 'package:gitopen/application/git/git_read_operations.dart';
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
import 'package:gitopen/infrastructure/git/git_cli_file_reader.dart';
import 'package:gitopen/infrastructure/git/git_cli_log_reader.dart';
import 'package:gitopen/infrastructure/git/git_cli_ref_reader.dart';
import 'package:gitopen/infrastructure/git/git_cli_status_reader.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';

/// Thin facade over the per-concern CLI readers.
///
/// Owns nothing but the wiring: one [GitProcessRunner] shared by a
/// [GitCliStatusReader] (status), [GitCliLogReader] (commit history),
/// [GitCliRefReader] (branches/tags/remotes/stashes/submodules) and
/// [GitCliFileReader] (diff/tree/blame/working file).  Every interface method
/// is a one-line delegation, so behaviour lives in exactly one collaborator.
final class GitCliReadOperations implements GitReadOperations {
  GitCliReadOperations({GitProcessRunner? runner}) {
    final r = runner ?? GitProcessRunner();
    _status = GitCliStatusReader(r);
    _log = GitCliLogReader(r);
    _refs = GitCliRefReader(r);
    _files = GitCliFileReader(r);
  }

  late final GitCliStatusReader _status;
  late final GitCliLogReader _log;
  late final GitCliRefReader _refs;
  late final GitCliFileReader _files;

  @override
  Future<RepoStatus> getStatus(RepoLocation repo) => _status.getStatus(repo);

  @override
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query) =>
      _log.getCommits(repo, query);

  @override
  Future<String?> getCommitFullMessage(RepoLocation repo, CommitSha sha) =>
      _log.getCommitFullMessage(repo, sha);

  @override
  Future<List<CommitInfo>> getFileHistory(
    RepoLocation repo,
    String path, {
    int? take,
  }) =>
      _log.getFileHistory(repo, path, take: take);

  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) =>
      _refs.getLocalBranches(repo);

  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) =>
      _refs.getRemoteBranches(repo);

  @override
  Future<List<Branch>> getBranches(RepoLocation repo) =>
      _refs.getBranches(repo);

  @override
  Future<List<Tag>> getTags(RepoLocation repo) => _refs.getTags(repo);

  @override
  Future<List<Remote>> getRemotes(RepoLocation repo) => _refs.getRemotes(repo);

  @override
  Future<List<Stash>> getStashes(RepoLocation repo) => _refs.getStashes(repo);

  @override
  Future<List<Submodule>> getSubmodules(RepoLocation repo) =>
      _refs.getSubmodules(repo);

  @override
  Future<DiffResult> getDiff(RepoLocation repo, DiffSpec spec) =>
      _files.getDiff(repo, spec);

  @override
  Future<List<FileTreeEntry>> getFileTree(
    RepoLocation repo,
    CommitSha sha,
    String path,
  ) =>
      _files.getFileTree(repo, sha, path);

  @override
  Future<List<BlameLine>> getBlame(
    RepoLocation repo,
    String path, {
    CommitSha? at,
  }) =>
      _files.getBlame(repo, path, at: at);

  @override
  Future<String> readWorkingFile(RepoLocation repo, String relativePath) =>
      _files.readWorkingFile(repo, relativePath);
}
