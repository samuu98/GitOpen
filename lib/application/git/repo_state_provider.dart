import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../domain/repositories/repo_location.dart';

enum InProgressOp { none, merge, cherryPick, rebase }

final repoStateProvider =
    FutureProvider.family.autoDispose<InProgressOp, RepoLocation>(
        (ref, repo) async {
  Future<bool> exists(String name) =>
      File(p.join(repo.path, '.git', name)).exists();
  if (await exists('MERGE_HEAD')) return InProgressOp.merge;
  if (await exists('CHERRY_PICK_HEAD')) return InProgressOp.cherryPick;
  if (await exists('REBASE_HEAD')) return InProgressOp.rebase;
  return InProgressOp.none;
});
