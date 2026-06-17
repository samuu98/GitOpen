abstract interface class WorkspacePersistence {
  Future<String?> getLastActiveRepoId();
  Future<void> saveLastActiveRepoId(String? id);
}
