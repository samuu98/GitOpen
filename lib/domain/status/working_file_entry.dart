import 'package:equatable/equatable.dart';

enum WorkingFileState {
  unmodified,
  added,
  modified,
  deleted,
  renamed,
  conflicted,
  untracked,
  ignored,
}

final class WorkingFileEntry extends Equatable {
  final String path;
  final WorkingFileState indexState;
  final WorkingFileState workingTreeState;
  final String? oldPath;

  const WorkingFileEntry({
    required this.path,
    required this.indexState,
    required this.workingTreeState,
    this.oldPath,
  });

  @override
  List<Object?> get props => [path, indexState, workingTreeState, oldPath];
}
