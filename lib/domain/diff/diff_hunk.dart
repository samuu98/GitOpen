import 'package:equatable/equatable.dart';

import 'diff_line.dart';

final class DiffHunk extends Equatable {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String header;
  final List<DiffLine> lines;

  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.header,
    required this.lines,
  });

  @override
  List<Object?> get props => [oldStart, oldCount, newStart, newCount, header, lines];
}
