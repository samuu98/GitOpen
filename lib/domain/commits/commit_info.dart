import 'package:equatable/equatable.dart';

import 'commit_sha.dart';
import 'commit_signature.dart';

final class CommitInfo extends Equatable {
  final CommitSha sha;
  final List<CommitSha> parentShas;
  final CommitSignature author;
  final CommitSignature committer;
  final String summary;
  final String message;

  const CommitInfo({
    required this.sha,
    required this.parentShas,
    required this.author,
    required this.committer,
    required this.summary,
    required this.message,
  });

  @override
  List<Object?> get props => [sha, parentShas, author, committer, summary, message];
}
