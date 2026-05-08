import 'package:equatable/equatable.dart';

import '../commits/commit_sha.dart';

enum FileTreeKind { blob, tree, submodule, symlink }

final class FileTreeEntry extends Equatable {
  final String name;
  final String fullPath;
  final FileTreeKind kind;
  final int? sizeBytes;
  final CommitSha? containingCommit;

  const FileTreeEntry({
    required this.name,
    required this.fullPath,
    required this.kind,
    this.sizeBytes,
    this.containingCommit,
  });

  @override
  List<Object?> get props => [name, fullPath, kind, sizeBytes, containingCommit];
}
