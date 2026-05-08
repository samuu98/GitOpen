import 'package:equatable/equatable.dart';

import 'diff_hunk.dart';

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
  final String path;
  final String? oldPath;
  final FileChangeKind changeKind;
  final bool isBinary;
  final int linesAdded;
  final int linesDeleted;
  final List<DiffHunk> hunks;

  const FileDiff({
    required this.path,
    this.oldPath,
    required this.changeKind,
    required this.isBinary,
    required this.linesAdded,
    required this.linesDeleted,
    required this.hunks,
  });

  @override
  List<Object?> get props => [
        path,
        oldPath,
        changeKind,
        isBinary,
        linesAdded,
        linesDeleted,
        hunks,
      ];
}
