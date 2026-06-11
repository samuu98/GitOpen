import 'package:equatable/equatable.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';

/// Which version of a file a byte-level read targets.
sealed class FileRevision extends Equatable {
  const FileRevision();

  @override
  List<Object?> get props => const [];
}

/// The blob committed at [commitSha].
final class FileRevisionAtCommit extends FileRevision {
  const FileRevisionAtCommit(this.commitSha);
  final CommitSha commitSha;

  @override
  List<Object?> get props => [commitSha];
}

/// The blob at [commitSha]'s FIRST parent — the "old" side of a
/// commit-vs-parent diff. Missing for root commits.
final class FileRevisionParentOfCommit extends FileRevision {
  const FileRevisionParentOfCommit(this.commitSha);
  final CommitSha commitSha;

  @override
  List<Object?> get props => [commitSha];
}

/// The blob at HEAD (old side of a staged diff).
final class FileRevisionHead extends FileRevision {
  const FileRevisionHead();
}

/// The blob staged in the index (stage 0).
final class FileRevisionIndex extends FileRevision {
  const FileRevisionIndex();
}

/// The bytes currently on disk in the working tree.
final class FileRevisionWorkingTree extends FileRevision {
  const FileRevisionWorkingTree();
}
