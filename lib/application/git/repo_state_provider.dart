import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../domain/repositories/repo_location.dart';
import '../providers.dart';
import '../repo_revision.dart';

enum InProgressOp { none, merge, cherryPick, rebase, revert }

final repoStateProvider =
    FutureProvider.family.autoDispose<InProgressOp, RepoLocation>(
        (ref, repo) async {
  ref.watch(repoRevisionProvider(repo));
  // Resolve the real git directory rather than assuming `<path>/.git`.
  // In a linked worktree or submodule `.git` is a file pointing elsewhere,
  // and MERGE_HEAD / rebase-merge live in that resolved dir — assuming
  // `<path>/.git/` there would always report `none` and the conflict panel
  // would never appear.
  String gitDir;
  try {
    final out = await ref
        .watch(gitProcessRunnerProvider)
        .run(repo.path, ['rev-parse', '--absolute-git-dir']);
    gitDir = out.trim();
    if (gitDir.isEmpty) return InProgressOp.none;
  } catch (_) {
    return InProgressOp.none; // not a git repo / git unavailable
  }

  Future<bool> fileExists(String name) =>
      File(p.join(gitDir, name)).exists();
  Future<bool> dirExists(String name) =>
      Directory(p.join(gitDir, name)).exists();
  if (await fileExists('MERGE_HEAD')) return InProgressOp.merge;
  if (await fileExists('CHERRY_PICK_HEAD')) return InProgressOp.cherryPick;
  // `git rebase` creates one of these dirs while paused on a conflict;
  // REBASE_HEAD alone is unreliable (set by interactive rebase only).
  if (await dirExists('rebase-merge') || await dirExists('rebase-apply')) {
    return InProgressOp.rebase;
  }
  if (await fileExists('REVERT_HEAD')) return InProgressOp.revert;
  return InProgressOp.none;
});
