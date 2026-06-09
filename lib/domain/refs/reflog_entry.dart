import 'package:equatable/equatable.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';

/// One `git reflog` row: where HEAD pointed ([sha]), the reflog selector
/// (`HEAD@{n}`) and git's action message ("commit: …", "checkout: …").
final class ReflogEntry extends Equatable {
  const ReflogEntry({
    required this.sha,
    required this.selector,
    required this.message,
  });
  final CommitSha sha;
  final String selector;
  final String message;

  @override
  List<Object?> get props => [sha, selector, message];
}
