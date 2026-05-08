import 'package:equatable/equatable.dart';

final class CommitSha extends Equatable {
  final String value;

  CommitSha(String input) : value = _normalize(input);

  static String _normalize(String input) {
    if (input.trim().isEmpty) {
      throw ArgumentError('CommitSha cannot be empty');
    }
    if (input.length < 4 || input.length > 40) {
      throw ArgumentError('CommitSha must be 4..40 hex chars');
    }
    return input.toLowerCase();
  }

  String short([int length = 7]) =>
      value.length <= length ? value : value.substring(0, length);

  @override
  String toString() => value;

  @override
  List<Object?> get props => [value];
}
