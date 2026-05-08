import 'package:equatable/equatable.dart';

import '../commits/commit_sha.dart';

final class Stash extends Equatable {
  final int index;
  final CommitSha sha;
  final String message;
  final DateTime createdAt;

  const Stash({
    required this.index,
    required this.sha,
    required this.message,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [index, sha, message, createdAt];
}
