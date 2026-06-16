/// Discovers git repositories inside a parent folder so the UI can open a whole
/// folder of repos at once. Scans only immediate subdirectories (depth 1).
// ignore: one_member_abstracts
abstract interface class RepoFolderScanner {
  /// Absolute paths of git repositories that are immediate children of
  /// [parentPath], sorted by path. Empty when the parent is missing or has
  /// none.
  Future<List<String>> findRepositories(String parentPath);
}
