import 'package:equatable/equatable.dart';

import '../commits/commit_sha.dart';

final class Tag extends Equatable {
  final String name;
  final String fullName;
  final CommitSha targetSha;
  final bool isAnnotated;

  const Tag({
    required this.name,
    required this.fullName,
    required this.targetSha,
    required this.isAnnotated,
  });

  @override
  List<Object?> get props => [name, fullName, targetSha, isAnnotated];
}
