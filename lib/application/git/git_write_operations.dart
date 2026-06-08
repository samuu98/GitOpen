import 'package:gitopen/application/git/auth_spec.dart';
import 'package:gitopen/application/git/commit_request.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

enum PullStrategy { ffOnly, merge, rebase }
enum ResetMode { soft, mixed, hard }

/// A single action in an interactive-rebase todo list. `reword`/`edit` are
/// intentionally omitted — they require interactive message/commit editing,
/// which is out of scope for this feature.
enum RebaseTodoAction { pick, squash, fixup, drop }

/// One line of a generated interactive-rebase instruction list: apply
/// [action] to the commit [sha]. Entries are supplied to
/// [GitWriteOperations.interactiveRebase] in the desired FINAL order,
/// OLDEST-FIRST (the same order git writes its instruction sheet).
final class RebaseTodoEntry {
  const RebaseTodoEntry(this.sha, this.action);
  final CommitSha sha;
  final RebaseTodoAction action;
}

abstract interface class GitWriteOperations {
  Future<GitResult<void>> stageFiles(RepoLocation r, List<String> paths);
  Future<GitResult<void>> unstageFiles(RepoLocation r, List<String> paths);
  Future<GitResult<void>> stagePatch(RepoLocation r, String unifiedDiff);
  Future<GitResult<void>> unstagePatch(RepoLocation r, String unifiedDiff);
  Future<GitResult<void>> discardChanges(RepoLocation r, List<String> paths);
  /// Deletes untracked paths from the working tree. Untracked files cannot
  /// be restored via `checkout`, so the only way to "discard" them is to
  /// remove them. Mirrors `git clean -f -- <paths>` (no `-d`).
  Future<GitResult<void>> cleanUntracked(RepoLocation r, List<String> paths);

  Future<GitResult<CommitSha>> commit(RepoLocation r, CommitRequest req);

  Future<GitResult<void>> createBranch(RepoLocation r, String name,
      {CommitSha? at, bool checkout = false});
  Future<GitResult<void>> checkout(
    RepoLocation r,
    String ref, {
    bool force = false,
  });
  Future<GitResult<void>> deleteBranch(RepoLocation r, String name,
      {bool force = false, bool remote = false});
  Future<GitResult<void>> renameBranch(
    RepoLocation r,
    String oldName,
    String newName,
  );
  Future<GitResult<void>> setUpstream(
    RepoLocation r,
    String branch,
    String upstream,
  );

  Future<GitResult<void>> addRemote(RepoLocation r, String name, String url);
  Future<GitResult<void>> removeRemote(RepoLocation r, String name);
  Future<GitResult<void>> renameRemote(
    RepoLocation r,
    String oldName,
    String newName,
  );
  Future<GitResult<void>> setRemoteUrl(RepoLocation r, String name, String url);

  Future<GitResult<void>> createTag(RepoLocation r, String name,
      {CommitSha? at, String? message});
  Future<GitResult<void>> deleteTag(RepoLocation r, String name);

  Stream<GitProgress> fetch(
    RepoLocation r, {
    String? remote,
    bool all = false,
    AuthSpec? auth,
  });
  Stream<GitProgress> pull(
    RepoLocation r,
    PullStrategy strategy, {
    AuthSpec? auth,
  });
  Stream<GitProgress> push(
    RepoLocation r, {
    String? remote,
    String? branch,
    bool forceWithLease = false,
    bool pushTags = false,
    AuthSpec? auth,
  });

  Future<GitResult<void>> stashSave(
    RepoLocation r,
    String message, {
    bool includeUntracked = false,
  });
  Future<GitResult<void>> stashPop(RepoLocation r, int index);
  Future<GitResult<void>> stashApply(RepoLocation r, int index);
  Future<GitResult<void>> stashDrop(RepoLocation r, int index);

  Future<GitResult<MergeOutcome>> merge(RepoLocation r, String ref,
      {MergeStrategy strategy = MergeStrategy.defaultStrategy});
  Future<GitResult<void>> mergeAbort(RepoLocation r);
  Future<GitResult<CommitSha>> mergeContinue(RepoLocation r);

  /// Dry-run check: does merging [ref] into HEAD produce conflicts?
  /// Implemented with `git merge-tree` so the working tree is not touched.
  Future<GitResult<MergePreview>> previewMerge(RepoLocation r, String ref);

  Future<GitResult<CherryPickOutcome>> cherryPick(
    RepoLocation r,
    CommitSha sha,
  );
  Future<GitResult<void>> cherryPickAbort(RepoLocation r);
  Future<GitResult<CommitSha>> cherryPickContinue(RepoLocation r);

  Future<GitResult<RevertOutcome>> revert(RepoLocation r, CommitSha sha);
  Future<GitResult<void>> revertAbort(RepoLocation r);
  Future<GitResult<CommitSha>> revertContinue(RepoLocation r);

  Future<GitResult<void>> reset(RepoLocation r, CommitSha to, ResetMode mode);

  Future<GitResult<RebaseOutcome>> rebase(RepoLocation r, String upstream);

  /// Runs a non-interactive *interactive* rebase: replays [plan] onto [onto]
  /// using a scripted todo list, with no editor prompts. [plan] lists the
  /// commits in their desired FINAL order, OLDEST-FIRST (git todo order);
  /// `squash`/`fixup` fold a commit into the entry above it, `drop` removes it.
  /// Returns the same [RebaseOutcome] variants as [rebase].
  Future<GitResult<RebaseOutcome>> interactiveRebase(
    RepoLocation r,
    CommitSha onto,
    List<RebaseTodoEntry> plan,
  );

  Future<GitResult<void>> rebaseAbort(RepoLocation r);
  Future<GitResult<CommitSha>> rebaseContinue(RepoLocation r);
  Future<GitResult<void>> rebaseSkip(RepoLocation r);

  Stream<GitProgress> clone(String url, String destination, {AuthSpec? auth});
}
