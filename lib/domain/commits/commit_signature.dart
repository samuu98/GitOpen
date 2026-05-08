import 'package:equatable/equatable.dart';

final class CommitSignature extends Equatable {
  final String name;
  final String email;
  final DateTime when;

  const CommitSignature(this.name, this.email, this.when);

  @override
  List<Object?> get props => [name, email, when];
}
