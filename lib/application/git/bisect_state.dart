import 'package:gitopen/domain/commits/commit_sha.dart';

/// Git's current bisect bounds and checked-out candidate.
final class BisectState {
  const BisectState({
    required this.candidate,
    required this.subject,
    required this.good,
    required this.bad,
    required this.stepsLeft,
    this.firstBad,
  });

  final CommitSha candidate;
  final String subject;
  final List<CommitSha> good;
  final CommitSha bad;
  final int stepsLeft;
  final CommitSha? firstBad;
}
