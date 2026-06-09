import 'dart:convert';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/infrastructure/persistence/database.dart';

class SettingsRepository implements SettingsStore {
  SettingsRepository(this._db);
  final AppDatabase _db;

  @override
  Future<Map<String, dynamic>> readAll() async {
    final rows = await _db.select(_db.settings).get();
    final result = <String, dynamic>{};
    for (final row in rows) {
      try {
        result[row.key] = jsonDecode(row.valueJson);
      } on Object catch (_) {
        // tolerate legacy raw strings
        result[row.key] = row.valueJson;
      }
    }
    return result;
  }

  @override
  Future<void> put(String key, dynamic value) async {
    final json = jsonEncode(value);
    await _db.into(_db.settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: key, valueJson: json),
    );
  }
}
