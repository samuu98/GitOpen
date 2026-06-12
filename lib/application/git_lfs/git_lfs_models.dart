import 'package:equatable/equatable.dart';

final class GitLfsStatus extends Equatable {
  const GitLfsStatus({
    required this.isInstalled,
    required this.version,
    required this.isRepoConfigured,
    required this.hasAttributes,
  });

  final bool isInstalled;
  final String? version;
  final bool isRepoConfigured;
  final bool hasAttributes;

  @override
  List<Object?> get props => [
    isInstalled,
    version,
    isRepoConfigured,
    hasAttributes,
  ];
}

final class GitLfsTrackedPattern extends Equatable {
  const GitLfsTrackedPattern({
    required this.pattern,
    required this.attributes,
    required this.source,
  });

  final String pattern;
  final String attributes;
  final String source;

  @override
  List<Object?> get props => [pattern, attributes, source];
}

final class GitLfsFile extends Equatable {
  const GitLfsFile({
    required this.oid,
    required this.path,
    required this.sizeLabel,
  });

  final String oid;
  final String path;
  final String sizeLabel;

  @override
  List<Object?> get props => [oid, path, sizeLabel];
}
