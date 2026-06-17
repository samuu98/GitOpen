import 'dart:convert';
import 'package:gitopen/application/workspaces/workspace_persistence.dart';
import 'package:gitopen/infrastructure/persistence/database.dart';

const String _key = 'last_active_repo';

final class DriftWorkspacePersistence implements WorkspacePersistence {
  DriftWorkspacePersistence(this._db);
  final AppDatabase _db;

  @override
  Future<String?> getLastActiveRepoId() async {
    final row = await (_db.select(_db.settings)
          ..where((s) => s.key.equals(_key)))
        .getSingleOrNull();
    if (row == null) return null;
    final decoded = jsonDecode(row.valueJson);
    return decoded is String ? decoded : null;
  }

  @override
  Future<void> saveLastActiveRepoId(String? id) async {
    await _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: _key, valueJson: jsonEncode(id)),
        );
  }
}
