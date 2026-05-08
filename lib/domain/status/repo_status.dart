import 'package:equatable/equatable.dart';

import '../commits/commit_sha.dart';
import 'working_file_entry.dart';

final class RepoStatus extends Equatable {
  final String? currentBranch;
  final CommitSha? headSha;
  final bool isDetached;
  final bool isBare;
  final List<WorkingFileEntry> entries;

  const RepoStatus({
    this.currentBranch,
    this.headSha,
    required this.isDetached,
    required this.isBare,
    required this.entries,
  });

  @override
  List<Object?> get props => [currentBranch, headSha, isDetached, isBare, entries];
}
