import 'package:equatable/equatable.dart';

import 'branch.dart';

final class Remote extends Equatable {
  final String name;
  final String url;
  final List<Branch> branches;

  const Remote({
    required this.name,
    required this.url,
    required this.branches,
  });

  @override
  List<Object?> get props => [name, url, branches];
}
