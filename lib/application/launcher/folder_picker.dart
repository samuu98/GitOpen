/// Lets application flows ask the user for a directory without depending on
/// the platform file-selector plugin (implemented in the UI shell).
// ignore: one_member_abstracts
abstract interface class FolderPicker {
  /// Opens the system directory picker; null when the user cancels.
  Future<String?> pickFolder(String title);
}
