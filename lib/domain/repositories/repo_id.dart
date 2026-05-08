import 'dart:math' as math;

import 'package:equatable/equatable.dart';

final class RepoId extends Equatable {
  final String value;

  const RepoId(this.value);

  factory RepoId.newId() {
    final r = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return RepoId(bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
  }

  @override
  List<Object?> get props => [value];

  @override
  String toString() => value;
}
