import 'package:equatable/equatable.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';

/// One entry of `git worktree list`: the checkout [path], the branch checked
/// out there (null when detached or bare) and its HEAD.
final class Worktree extends Equatable {
  const Worktree({
    required this.path,
    this.branch,
    this.headSha,
    this.isBare = false,
    this.isDetached = false,
  });
  final String path;
  final String? branch;
  final CommitSha? headSha;
  final bool isBare;
  final bool isDetached;

  @override
  List<Object?> get props => [path, branch, headSha, isBare, isDetached];
}
