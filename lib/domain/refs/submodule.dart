import 'package:equatable/equatable.dart';

import 'package:gitopen/domain/commits/commit_sha.dart';

/// Lifecycle/working-tree state of a submodule, derived from the leading
/// status character of a `git submodule status` line.
enum SubmoduleStatus {
  /// Not initialized — the submodule's working tree is absent (`-`).
  uninitialized,

  /// Checked out at the SHA the superproject records (` `).
  upToDate,

  /// Checked out at a different SHA than recorded, i.e. there are local
  /// changes in the submodule's working tree (`+`).
  modified,

  /// The submodule has merge conflicts (`U`).
  mergeConflict,
}

/// A git submodule entry as reported by `git submodule status`.
final class Submodule extends Equatable {
  const Submodule({
    required this.path,
    required this.sha,
    required this.status,
    this.describe,
  });

  /// Path of the submodule relative to the superproject root.
  final String path;

  /// The commit the submodule is currently at (uninitialized submodules
  /// report the SHA the superproject expects).
  final CommitSha sha;

  /// Optional `git describe` output for [sha], in parentheses in the raw
  /// status line. Null when git emits no describe (e.g. uninitialized).
  final String? describe;

  /// Working-tree state derived from the status line's leading character.
  final SubmoduleStatus status;

  @override
  List<Object?> get props => [path, sha, describe, status];
}
