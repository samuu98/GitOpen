import 'package:equatable/equatable.dart';

import '../commits/commit_sha.dart';

sealed class DiffSpec extends Equatable {
  const DiffSpec();
}

final class DiffSpecCommitVsParent extends DiffSpec {
  final CommitSha commitSha;

  const DiffSpecCommitVsParent(this.commitSha);

  @override
  List<Object?> get props => [commitSha];
}

final class DiffSpecCommitVsCommit extends DiffSpec {
  final CommitSha from;
  final CommitSha to;

  const DiffSpecCommitVsCommit(this.from, this.to);

  @override
  List<Object?> get props => [from, to];
}

final class DiffSpecIndexVsHead extends DiffSpec {
  const DiffSpecIndexVsHead();

  @override
  List<Object?> get props => const [];
}

final class DiffSpecWorkingTreeVsIndex extends DiffSpec {
  const DiffSpecWorkingTreeVsIndex();

  @override
  List<Object?> get props => const [];
}
