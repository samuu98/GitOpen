import 'package:equatable/equatable.dart';

enum DiffLineKind { context, addition, deletion }

final class DiffLine extends Equatable {
  final DiffLineKind kind;
  final int? oldLine;
  final int? newLine;
  final String content;

  const DiffLine({
    required this.kind,
    this.oldLine,
    this.newLine,
    required this.content,
  });

  @override
  List<Object?> get props => [kind, oldLine, newLine, content];
}
