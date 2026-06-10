import 'package:equatable/equatable.dart';

import 'package:gitopen/domain/diff/diff_hunk.dart';

enum FileChangeKind {
  added,
  deleted,
  modified,
  renamed,
  copied,
  typeChanged,
  unmerged,
}

final class FileDiff extends Equatable {

  const FileDiff({
    required this.path,
    required this.changeKind,
    required this.isBinary,
    required this.linesAdded,
    required this.linesDeleted,
    required this.hunks,
    this.oldPath,
    this.truncated = false,
  });
  final String path;
  final String? oldPath;
  final FileChangeKind changeKind;
  final bool isBinary;
  final int linesAdded;
  final int linesDeleted;
  final List<DiffHunk> hunks;

  /// True when [hunks] were cut at the read-facade line cap; fetch the file
  /// alone (`getDiffForFile`) for the full diff.
  final bool truncated;

  @override
  List<Object?> get props => [
        path,
        oldPath,
        changeKind,
        isBinary,
        linesAdded,
        linesDeleted,
        hunks,
        truncated,
      ];
}
