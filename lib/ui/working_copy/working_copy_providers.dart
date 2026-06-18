import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';

final workingCopyStatusProvider =
    FutureProvider.family.autoDispose<List<WorkingFileEntry>, RepoLocation>(
  (ref, repo) async {
    final git = ref.watch(gitReadOperationsProvider);
    final status = await git.getStatus(repo);
    return status.entries;
  },
);

/// Currently selected file path in the working copy panel.
/// `null` means no preview is shown.
final selectedFileProvider =
    StateProvider.autoDispose<({String path, bool staged})?>((_) => null);

/// Working-tree-vs-index diff, keyed by (repo, filePath).
final unstagedFileDiffProvider = FutureProvider.family
    .autoDispose<FileDiff?, (RepoLocation, String)>((ref, args) async {
  final (repo, filePath) = args;
  final git = ref.read(gitReadOperationsProvider);
  final result = await git.getDiff(repo, const DiffSpecWorkingTreeVsIndex());
  try {
    return result.files.firstWhere((f) => f.path == filePath);
  } on Object catch (_) {
    return null;
  }
});

/// Index-vs-HEAD diff, keyed by (repo, filePath).
final stagedFileDiffProvider = FutureProvider.family
    .autoDispose<FileDiff?, (RepoLocation, String)>((ref, args) async {
  final (repo, filePath) = args;
  final git = ref.read(gitReadOperationsProvider);
  final result = await git.getDiff(repo, const DiffSpecIndexVsHead());
  try {
    return result.files.firstWhere((f) => f.path == filePath);
  } on Object catch (_) {
    return null;
  }
});
