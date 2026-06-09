/// Persistence port for app settings (implemented over the app database in
/// infrastructure), so the settings notifier stays storage-agnostic.
abstract interface class SettingsStore {
  /// All persisted settings, decoded from their stored representation.
  Future<Map<String, dynamic>> readAll();

  /// Persists [value] (JSON-encodable) under [key].
  Future<void> put(String key, dynamic value);
}
