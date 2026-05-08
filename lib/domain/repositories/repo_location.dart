import 'package:equatable/equatable.dart';

import 'repo_id.dart';

final class RepoLocation extends Equatable {
  final RepoId id;
  final String path;
  final String displayName;

  const RepoLocation(this.id, this.path, this.displayName);

  @override
  List<Object?> get props => [id, path, displayName];
}
