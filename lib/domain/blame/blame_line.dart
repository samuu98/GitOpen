import 'package:equatable/equatable.dart';

import 'package:gitopen/domain/commits/commit_sha.dart';

/// A single line of a file annotated with the commit that last touched it,
/// as produced by `git blame --porcelain`.
final class BlameLine extends Equatable {
  const BlameLine({
    required this.lineNumber,
    required this.content,
    required this.sha,
    required this.authorName,
    required this.authorTime,
  });

  /// 1-based line number in the final version of the file.
  final int lineNumber;

  /// The line's text content (without the trailing newline).
  final String content;

  /// The commit that introduced this line in its current form.
  final CommitSha sha;

  /// Display name of the author of [sha].
  final String authorName;

  /// Author time of [sha].
  final DateTime authorTime;

  @override
  List<Object?> get props => [lineNumber, content, sha, authorName, authorTime];
}
