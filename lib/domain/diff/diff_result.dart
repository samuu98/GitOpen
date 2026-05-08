import 'package:equatable/equatable.dart';

import 'file_diff.dart';

final class DiffResult extends Equatable {
  final List<FileDiff> files;

  const DiffResult({required this.files});

  @override
  List<Object?> get props => [files];
}
