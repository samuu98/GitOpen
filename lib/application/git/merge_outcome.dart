import 'package:gitopen/domain/commits/commit_sha.dart';

/// Selects how a merge is performed.
/// - [defaultStrategy]: fast-forward if possible, otherwise create a merge
///   commit.
/// - [noFF]: always create a merge commit (`--no-ff`).
/// - [squash]: collapse all changes into a single, uncommitted index update
///   (`--squash`).
/// - [noCommit]: prepare the merge but leave the commit to the user
///   (`--no-commit`).
enum MergeStrategy { defaultStrategy, noFF, squash, noCommit }

/// Result of a dry-run merge check (`git merge-tree`).
sealed class MergePreview {
  const MergePreview();
}

final class MergePreviewClean extends MergePreview {
  const MergePreviewClean();
}

final class MergePreviewConflicts extends MergePreview {
  const MergePreviewConflicts(this.conflictedPaths);
  final List<String> conflictedPaths;
}

sealed class MergeOutcome {
  const MergeOutcome();
}

final class MergeFastForward extends MergeOutcome {
  const MergeFastForward(this.newHead);
  final CommitSha newHead;
}

final class MergeMerged extends MergeOutcome {
  const MergeMerged(this.mergeCommit);
  final CommitSha mergeCommit;
}

/// The working tree changed but no commit was created — produced by `--squash`
/// and `--no-commit` strategies. The user is expected to commit manually.
final class MergeStaged extends MergeOutcome {
  const MergeStaged();
}

final class MergeUpToDate extends MergeOutcome {
  const MergeUpToDate();
}

final class MergeConflict extends MergeOutcome {
  const MergeConflict(this.conflictedPaths);
  final List<String> conflictedPaths;
}

sealed class CherryPickOutcome {
  const CherryPickOutcome();
}

final class CherryPickApplied extends CherryPickOutcome {
  const CherryPickApplied(this.newCommit);
  final CommitSha newCommit;
}

final class CherryPickConflict extends CherryPickOutcome {
  const CherryPickConflict(this.conflictedPaths);
  final List<String> conflictedPaths;
}

sealed class RevertOutcome {
  const RevertOutcome();
}

final class RevertApplied extends RevertOutcome {
  const RevertApplied(this.newCommit);
  final CommitSha newCommit;
}

final class RevertConflict extends RevertOutcome {
  const RevertConflict(this.conflictedPaths);
  final List<String> conflictedPaths;
}

sealed class RebaseOutcome {
  const RebaseOutcome();
}

final class RebaseApplied extends RebaseOutcome {
  const RebaseApplied(this.newHead);
  final CommitSha newHead;
}

final class RebaseUpToDate extends RebaseOutcome {
  const RebaseUpToDate();
}

final class RebaseConflict extends RebaseOutcome {
  const RebaseConflict(this.conflictedPaths);
  final List<String> conflictedPaths;
}

/// The rebase intentionally paused at a commit marked `edit` — the user can
/// now amend it and then continue (or abort) the rebase.
final class RebaseStoppedForEdit extends RebaseOutcome {
  const RebaseStoppedForEdit();
}
