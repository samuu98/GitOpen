import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

enum InProgressOp { none, merge, cherryPick, rebase, revert }

final repoStateProvider =
    FutureProvider.family.autoDispose<InProgressOp, RepoLocation>(
        (ref, repo) async {
  final probe = ref.watch(gitDirProbeProvider);
  if (probe.fileExists(repo, 'MERGE_HEAD')) return InProgressOp.merge;
  if (probe.fileExists(repo, 'CHERRY_PICK_HEAD')) {
    return InProgressOp.cherryPick;
  }
  // `git rebase` creates one of these dirs while paused on a conflict;
  // REBASE_HEAD alone is unreliable (set by interactive rebase only).
  if (probe.dirExists(repo, 'rebase-merge') ||
      probe.dirExists(repo, 'rebase-apply')) {
    return InProgressOp.rebase;
  }
  if (probe.fileExists(repo, 'REVERT_HEAD')) return InProgressOp.revert;
  return InProgressOp.none;
});
