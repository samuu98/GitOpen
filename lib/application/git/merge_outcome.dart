import '../../domain/commits/commit_sha.dart';

/// Selects how a merge is performed.
/// - [defaultStrategy]: fast-forward if possible, otherwise create a merge commit.
/// - [noFF]: always create a merge commit (`--no-ff`).
/// - [squash]: collapse all changes into a single, uncommitted index update (`--squash`).
/// - [noCommit]: prepare the merge but leave the commit to the user (`--no-commit`).
enum MergeStrategy { defaultStrategy, noFF, squash, noCommit }

/// Result of a dry-run merge check (`git merge-tree`).
sealed class MergePreview {
  const MergePreview();
}

final class MergePreviewClean extends MergePreview {
  const MergePreviewClean();
}

final class MergePreviewConflicts extends MergePreview {
  final List<String> conflictedPaths;
  const MergePreviewConflicts(this.conflictedPaths);
}

sealed class MergeOutcome {
  const MergeOutcome();
}

final class MergeFastForward extends MergeOutcome {
  final CommitSha newHead;
  const MergeFastForward(this.newHead);
}

final class MergeMerged extends MergeOutcome {
  final CommitSha mergeCommit;
  const MergeMerged(this.mergeCommit);
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
  final List<String> conflictedPaths;
  const MergeConflict(this.conflictedPaths);
}

sealed class CherryPickOutcome {
  const CherryPickOutcome();
}

final class CherryPickApplied extends CherryPickOutcome {
  final CommitSha newCommit;
  const CherryPickApplied(this.newCommit);
}

final class CherryPickConflict extends CherryPickOutcome {
  final List<String> conflictedPaths;
  const CherryPickConflict(this.conflictedPaths);
}

sealed class RevertOutcome {
  const RevertOutcome();
}

final class RevertApplied extends RevertOutcome {
  final CommitSha newCommit;
  const RevertApplied(this.newCommit);
}

final class RevertConflict extends RevertOutcome {
  final List<String> conflictedPaths;
  const RevertConflict(this.conflictedPaths);
}

sealed class RebaseOutcome {
  const RebaseOutcome();
}

final class RebaseApplied extends RebaseOutcome {
  final CommitSha newHead;
  const RebaseApplied(this.newHead);
}

final class RebaseUpToDate extends RebaseOutcome {
  const RebaseUpToDate();
}

final class RebaseConflict extends RebaseOutcome {
  final List<String> conflictedPaths;
  const RebaseConflict(this.conflictedPaths);
}
