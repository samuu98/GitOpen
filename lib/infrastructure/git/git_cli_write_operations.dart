import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/commit_request.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_ref_writer.dart';
import 'package:gitopen/infrastructure/git/git_cli_sequencer_writer.dart';
import 'package:gitopen/infrastructure/git/git_cli_sync_writer.dart';
import 'package:gitopen/infrastructure/git/git_cli_worktree_writer.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/git/git_result_runner.dart';

/// Thin facade over the per-concern CLI writers.
///
/// Owns nothing but the wiring: one [GitProcessRunner] (wrapped in a shared
/// [GitResultRunner] for failure classification) behind a
/// [GitCliWorktreeWriter] (stage/discard/commit), [GitCliRefWriter]
/// (branch/remote/tag/stash CRUD), [GitCliSequencerWriter]
/// (merge/rebase/cherry-pick/revert) and [GitCliSyncWriter]
/// (fetch/pull/push/clone).  Every interface method is a one-line delegation,
/// so behaviour lives in exactly one collaborator.
final class GitCliWriteOperations implements GitWriteOperations {
  GitCliWriteOperations({GitProcessRunner? runner}) {
    final r = runner ?? GitProcessRunner();
    final git = GitResultRunner(r);
    _worktree = GitCliWorktreeWriter(git);
    _refs = GitCliRefWriter(git);
    _sequencer = GitCliSequencerWriter(git);
    _sync = GitCliSyncWriter(r);
  }

  late final GitCliWorktreeWriter _worktree;
  late final GitCliRefWriter _refs;
  late final GitCliSequencerWriter _sequencer;
  late final GitCliSyncWriter _sync;

  // ---- Working tree / index ----------------------------------------------

  @override
  Future<GitResult<void>> initRepo(String directory) =>
      _worktree.initRepo(directory);

  @override
  Future<GitResult<void>> writeWorkingFile(
    RepoLocation r,
    String relativePath,
    String content,
  ) =>
      _worktree.writeWorkingFile(r, relativePath, content);

  @override
  Future<GitResult<void>> stageFiles(RepoLocation r, List<String> paths) =>
      _worktree.stageFiles(r, paths);

  @override
  Future<GitResult<void>> unstageFiles(RepoLocation r, List<String> paths) =>
      _worktree.unstageFiles(r, paths);

  @override
  Future<GitResult<void>> stagePatch(RepoLocation r, String unifiedDiff) =>
      _worktree.stagePatch(r, unifiedDiff);

  @override
  Future<GitResult<void>> unstagePatch(RepoLocation r, String unifiedDiff) =>
      _worktree.unstagePatch(r, unifiedDiff);

  @override
  Future<GitResult<void>> discardChanges(RepoLocation r, List<String> paths) =>
      _worktree.discardChanges(r, paths);

  @override
  Future<GitResult<void>> cleanUntracked(RepoLocation r, List<String> paths) =>
      _worktree.cleanUntracked(r, paths);

  @override
  Future<GitResult<CommitSha>> commit(RepoLocation r, CommitRequest req) =>
      _worktree.commit(r, req);

  // ---- Ref / stash CRUD ---------------------------------------------------

  @override
  Future<GitResult<void>> createBranch(
    RepoLocation r,
    String name, {
    CommitSha? at,
    bool checkout = false,
  }) =>
      _refs.createBranch(r, name, at: at, checkout: checkout);

  @override
  Future<GitResult<void>> checkout(
    RepoLocation r,
    String ref, {
    bool force = false,
  }) =>
      _refs.checkout(r, ref, force: force);

  @override
  Future<GitResult<void>> deleteBranch(
    RepoLocation r,
    String name, {
    bool force = false,
    bool remote = false,
  }) =>
      _refs.deleteBranch(r, name, force: force, remote: remote);

  @override
  Future<GitResult<void>> renameBranch(
    RepoLocation r,
    String oldName,
    String newName,
  ) =>
      _refs.renameBranch(r, oldName, newName);

  @override
  Future<GitResult<void>> setUpstream(
    RepoLocation r,
    String branch,
    String upstream,
  ) =>
      _refs.setUpstream(r, branch, upstream);

  @override
  Future<GitResult<void>> addRemote(RepoLocation r, String name, String url) =>
      _refs.addRemote(r, name, url);

  @override
  Future<GitResult<void>> removeRemote(RepoLocation r, String name) =>
      _refs.removeRemote(r, name);

  @override
  Future<GitResult<void>> renameRemote(
    RepoLocation r,
    String oldName,
    String newName,
  ) =>
      _refs.renameRemote(r, oldName, newName);

  @override
  Future<GitResult<void>> setRemoteUrl(
    RepoLocation r,
    String name,
    String url,
  ) =>
      _refs.setRemoteUrl(r, name, url);

  @override
  Future<GitResult<void>> createTag(
    RepoLocation r,
    String name, {
    CommitSha? at,
    String? message,
  }) =>
      _refs.createTag(r, name, at: at, message: message);

  @override
  Future<GitResult<void>> deleteTag(RepoLocation r, String name) =>
      _refs.deleteTag(r, name);

  @override
  Future<GitResult<void>> stashSave(
    RepoLocation r,
    String message, {
    bool includeUntracked = false,
  }) =>
      _refs.stashSave(r, message, includeUntracked: includeUntracked);

  @override
  Future<GitResult<void>> stashPop(RepoLocation r, int index) =>
      _refs.stashPop(r, index);

  @override
  Future<GitResult<void>> stashApply(RepoLocation r, int index) =>
      _refs.stashApply(r, index);

  @override
  Future<GitResult<void>> stashDrop(RepoLocation r, int index) =>
      _refs.stashDrop(r, index);

  @override
  Future<GitResult<void>> reset(RepoLocation r, CommitSha to, ResetMode mode) =>
      _refs.reset(r, to, mode);

  @override
  Future<GitResult<void>> updateSubmodule(
    RepoLocation r,
    String path, {
    bool init = true,
  }) =>
      _refs.updateSubmodule(r, path, init: init);

  @override
  Future<GitResult<void>> updateAllSubmodules(
    RepoLocation r, {
    bool init = true,
  }) =>
      _refs.updateAllSubmodules(r, init: init);

  // ---- Sequencing (merge/rebase/cherry-pick/revert) -----------------------

  @override
  Future<GitResult<MergeOutcome>> merge(RepoLocation r, String ref,
          {MergeStrategy strategy = MergeStrategy.defaultStrategy}) =>
      _sequencer.merge(r, ref, strategy: strategy);

  @override
  Future<GitResult<void>> mergeAbort(RepoLocation r) =>
      _sequencer.mergeAbort(r);

  @override
  Future<GitResult<CommitSha>> mergeContinue(RepoLocation r) =>
      _sequencer.mergeContinue(r);

  @override
  Future<GitResult<MergePreview>> previewMerge(RepoLocation r, String ref) =>
      _sequencer.previewMerge(r, ref);

  @override
  Future<GitResult<RebaseOutcome>> rebase(RepoLocation r, String upstream) =>
      _sequencer.rebase(r, upstream);

  @override
  Future<GitResult<RebaseOutcome>> interactiveRebase(
    RepoLocation r,
    CommitSha onto,
    List<RebaseTodoEntry> plan,
  ) =>
      _sequencer.interactiveRebase(r, onto, plan);

  @override
  Future<GitResult<void>> rebaseAbort(RepoLocation r) =>
      _sequencer.rebaseAbort(r);

  @override
  Future<GitResult<CommitSha>> rebaseContinue(RepoLocation r) =>
      _sequencer.rebaseContinue(r);

  @override
  Future<GitResult<void>> rebaseSkip(RepoLocation r) =>
      _sequencer.rebaseSkip(r);

  @override
  Future<GitResult<CherryPickOutcome>> cherryPick(
    RepoLocation r,
    CommitSha sha,
  ) =>
      _sequencer.cherryPick(r, sha);

  @override
  Future<GitResult<void>> cherryPickAbort(RepoLocation r) =>
      _sequencer.cherryPickAbort(r);

  @override
  Future<GitResult<CommitSha>> cherryPickContinue(RepoLocation r) =>
      _sequencer.cherryPickContinue(r);

  @override
  Future<GitResult<RevertOutcome>> revert(RepoLocation r, CommitSha sha) =>
      _sequencer.revert(r, sha);

  @override
  Future<GitResult<void>> revertAbort(RepoLocation r) =>
      _sequencer.revertAbort(r);

  @override
  Future<GitResult<CommitSha>> revertContinue(RepoLocation r) =>
      _sequencer.revertContinue(r);

  // ---- Remote sync (streaming) --------------------------------------------

  @override
  Stream<GitProgress> fetch(
    RepoLocation r, {
    String? remote,
    bool all = false,
    AuthSpec? auth,
  }) =>
      _sync.fetch(r, remote: remote, all: all, auth: auth);

  @override
  Stream<GitProgress> pull(
    RepoLocation r,
    PullStrategy strategy, {
    AuthSpec? auth,
  }) =>
      _sync.pull(r, strategy, auth: auth);

  @override
  Stream<GitProgress> push(
    RepoLocation r, {
    String? remote,
    String? branch,
    bool forceWithLease = false,
    bool pushTags = false,
    AuthSpec? auth,
  }) =>
      _sync.push(
        r,
        remote: remote,
        branch: branch,
        forceWithLease: forceWithLease,
        pushTags: pushTags,
        auth: auth,
      );

  @override
  Stream<GitProgress> clone(String url, String destination, {AuthSpec? auth}) =>
      _sync.clone(url, destination, auth: auth);
}
