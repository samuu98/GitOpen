/// Why a folder cannot be opened as a GitOpen workspace.
enum RepositoryValidationError { missing, notRepository }

/// A user-facing validation failure raised before a repository is persisted.
final class RepositoryValidationException implements Exception {
  const RepositoryValidationException(this.kind, this.message);

  final RepositoryValidationError kind;
  final String message;

  @override
  String toString() => message;
}

/// Validates and canonicalizes a repository working-tree path.
// ignore: one_member_abstracts
abstract interface class RepositoryValidator {
  /// Returns a stable absolute path or throws [RepositoryValidationException].
  Future<String> validate(String path);
}
