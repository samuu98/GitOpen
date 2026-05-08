abstract interface class WorkspacePersistence {
  Future<List<String>> getOpenPaths();
  Future<void> saveOpenPaths(List<String> paths);
}
