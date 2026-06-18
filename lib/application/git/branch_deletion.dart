import 'package:gitopen/domain/refs/branch.dart';

/// The deletable sides for a branch the user asked to delete.
class BranchDeletionTargets {
  const BranchDeletionTargets({
    this.localName,
    this.localIsCurrent = false,
    this.remoteRef,
  });

  /// Local branch short name (e.g. "feature"), or null when there is none.
  final String? localName;

  /// True when the local side is the checked-out branch (cannot be deleted).
  final bool localIsCurrent;

  /// Remote ref as `<remote>/<branch>` (e.g. "origin/feature"), or null.
  final String? remoteRef;
}

const _remotePrefix = 'refs/remotes/';

/// Maps the right-clicked [clicked] branch (plus the full [all] branch list)
/// to its local and remote deletion targets.
BranchDeletionTargets branchDeletionTargets(Branch clicked, List<Branch> all) {
  if (!clicked.isRemote) {
    final up = clicked.upstreamFullName;
    final remoteRef = (up != null && up.startsWith(_remotePrefix))
        ? up.substring(_remotePrefix.length)
        : null;
    return BranchDeletionTargets(
      localName: clicked.name,
      localIsCurrent: clicked.isCurrent,
      remoteRef: remoteRef,
    );
  }
  // Clicked a remote branch: find the local branch tracking it.
  Branch? trackingLocal;
  for (final b in all) {
    if (!b.isRemote && b.upstreamFullName == clicked.fullName) {
      trackingLocal = b;
      break;
    }
  }
  return BranchDeletionTargets(
    remoteRef: clicked.name,
    localName: trackingLocal?.name,
    localIsCurrent: trackingLocal?.isCurrent ?? false,
  );
}

/// True when [stderr] is git refusing `branch -d` because the branch has
/// commits not reachable from its upstream/HEAD.
bool isNotFullyMergedError(String stderr) =>
    stderr.toLowerCase().contains('not fully merged');
