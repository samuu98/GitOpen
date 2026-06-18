import 'dart:io';

import 'package:gitopen/application/diff/diff_cap.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/blame/blame_line.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/files/file_content.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/domain/files/file_tree_entry.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/reflog_entry.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/infrastructure/git/git_cli_file_reader.dart';
import 'package:gitopen/infrastructure/git/git_cli_log_reader.dart';
import 'package:gitopen/infrastructure/git/git_cli_ref_reader.dart';
import 'package:gitopen/infrastructure/git/git_cli_status_reader.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/git/git_result_runner.dart';

/// Thin facade over the per-concern CLI readers.
///
/// Owns nothing but the wiring: one [GitProcessRunner] shared by a
/// [GitCliStatusReader] (status), [GitCliLogReader] (commit history),
/// [GitCliRefReader] (branches/tags/remotes/stashes/submodules) and
/// [GitCliFileReader] (diff/tree/blame/working file).  Every interface method
/// is a one-line delegation, so behaviour lives in exactly one collaborator —
/// plus the error boundary: transport failures ([GitProcessException], file
/// system errors) are rethrown as the application-typed [GitReadException].
final class GitCliReadOperations implements GitReadOperations {
  GitCliReadOperations({GitProcessRunner? runner}) {
    final r = runner ?? GitProcessRunner();
    _classifier = GitResultRunner(r);
    _status = GitCliStatusReader(r);
    _log = GitCliLogReader(r);
    _refs = GitCliRefReader(r);
    _files = GitCliFileReader(r);
  }

  late final GitResultRunner _classifier;
  late final GitCliStatusReader _status;
  late final GitCliLogReader _log;
  late final GitCliRefReader _refs;
  late final GitCliFileReader _files;

  /// Maps transport failures to the typed application error. Reads have no
  /// result-wrapper like writes' `GitResult`, so the boundary is exceptions:
  /// classified kind + git's stderr only (never the argv dump).
  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on GitProcessException catch (e) {
      throw GitReadException(_classifier.classify(e), e.stderr.trim());
    } on FileSystemException catch (e) {
      throw GitReadException(GitErrorKind.other, e.message);
    }
  }

  @override
  Future<RepoStatus> getStatus(RepoLocation repo) =>
      _guard(() => _status.getStatus(repo));

  @override
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query) {
    // `yield*` would forward the inner stream's errors straight to the
    // subscriber, bypassing a try/catch — map them at the stream level.
    return _log
        .getCommits(repo, query)
        .handleError(
          (Object e) => throw GitReadException(
            _classifier.classify(e as GitProcessException),
            e.stderr.trim(),
          ),
          test: (e) => e is GitProcessException,
        );
  }

  @override
  Future<String?> getCommitFullMessage(RepoLocation repo, CommitSha sha) =>
      _guard(() => _log.getCommitFullMessage(repo, sha));

  @override
  Future<({int left, int right})> countDivergence(
    RepoLocation repo,
    CommitSha a,
    CommitSha b,
  ) => _guard(() => _log.countDivergence(repo, a, b));

  @override
  Future<List<CommitInfo>> getFileHistory(
    RepoLocation repo,
    String path, {
    int? take,
  }) => _guard(() => _log.getFileHistory(repo, path, take: take));

  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) =>
      _guard(() => _refs.getLocalBranches(repo));

  @override
  Future<Map<String, ({int ahead, int behind})>> localBranchDivergence(
    RepoLocation repo,
  ) =>
      _guard(() => _refs.localBranchDivergence(repo));

  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) =>
      _guard(() => _refs.getRemoteBranches(repo));

  @override
  Future<List<Branch>> getBranches(RepoLocation repo) =>
      _guard(() => _refs.getBranches(repo));

  @override
  Future<List<Tag>> getTags(RepoLocation repo) =>
      _guard(() => _refs.getTags(repo));

  @override
  Future<List<Remote>> getRemotes(RepoLocation repo) =>
      _guard(() => _refs.getRemotes(repo));

  @override
  Future<List<Stash>> getStashes(RepoLocation repo) =>
      _guard(() => _refs.getStashes(repo));

  @override
  Future<DiffResult> getStashDiff(RepoLocation repo, int index) =>
      _guard(() async => capDiffResult(await _files.getStashDiff(repo, index)));

  @override
  Future<List<ReflogEntry>> getReflog(RepoLocation repo, {int limit = 100}) =>
      _guard(() => _refs.getReflog(repo, limit: limit));

  @override
  Future<List<Worktree>> getWorktrees(RepoLocation repo) =>
      _guard(() => _refs.getWorktrees(repo));

  @override
  Future<List<Submodule>> getSubmodules(RepoLocation repo) =>
      _guard(() => _refs.getSubmodules(repo));

  @override
  Future<DiffResult> getDiff(
    RepoLocation repo,
    DiffSpec spec, {
    bool ignoreWhitespace = false,
  }) => _guard(
    () async => capDiffResult(
      await _files.getDiff(
        repo,
        spec,
        ignoreWhitespace: ignoreWhitespace,
      ),
    ),
  );

  @override
  Future<DiffResult> getDiffForFile(
    RepoLocation repo,
    DiffSpec spec,
    String path, {
    bool ignoreWhitespace = false,
  }) => _guard(
    () => _files.getDiff(
      repo,
      spec,
      path: path,
      ignoreWhitespace: ignoreWhitespace,
    ),
  );

  @override
  Future<List<FileTreeEntry>> getFileTree(
    RepoLocation repo,
    CommitSha sha,
    String path, {
    bool recursive = false,
  }) => _guard(() => _files.getFileTree(repo, sha, path, recursive: recursive));

  @override
  Future<List<BlameLine>> getBlame(
    RepoLocation repo,
    String path, {
    CommitSha? at,
  }) => _guard(() => _files.getBlame(repo, path, at: at));

  @override
  Future<FileContent> getFileBytes(
    RepoLocation repo,
    FileRevision revision,
    String path, {
    int maxBytes = kFilePreviewMaxBytes,
  }) => _guard(
    () => _files.getFileBytes(repo, revision, path, maxBytes: maxBytes),
  );

  @override
  Future<String> readWorkingFile(RepoLocation repo, String relativePath) =>
      _guard(() => _files.readWorkingFile(repo, relativePath));
}
