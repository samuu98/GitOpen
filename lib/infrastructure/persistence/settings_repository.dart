import 'dart:convert';
import 'database.dart';

class SettingsRepository {
  final AppDatabase _db;
  SettingsRepository(this._db);

  Future<Map<String, dynamic>> readAll() async {
    final rows = await _db.select(_db.settings).get();
    final result = <String, dynamic>{};
    for (final row in rows) {
      try {
        result[row.key] = jsonDecode(row.valueJson);
      } catch (_) {
        // tolerate legacy raw strings
        result[row.key] = row.valueJson;
      }
    }
    return result;
  }

  Future<void> put(String key, dynamic value) async {
    final json = jsonEncode(value);
    await _db.into(_db.settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: key, valueJson: json),
    );
  }
}
