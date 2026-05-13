import 'package:equatable/equatable.dart';

/// A saved git identity profile. The [label] is a human-readable nickname
/// (e.g. "Work", "Personal") shown in the UI; the [name] and [email] are
/// what get written to a repo's local config as `user.name` and `user.email`.
final class GitIdentity extends Equatable {
  final String label;
  final String name;
  final String email;
  const GitIdentity({
    required this.label,
    required this.name,
    required this.email,
  });

  Map<String, String> toJson() => {
        'label': label,
        'name': name,
        'email': email,
      };

  static GitIdentity? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    final name = raw['name'];
    final email = raw['email'];
    if (label is! String || name is! String || email is! String) return null;
    return GitIdentity(label: label, name: name, email: email);
  }

  @override
  List<Object?> get props => [label, name, email];
}
