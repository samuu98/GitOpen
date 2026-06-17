import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:gitopen/infrastructure/persistence/path_provider_helper.dart';
import 'package:gitopen/infrastructure/persistence/tables/activity_log_table.dart';
import 'package:gitopen/infrastructure/persistence/tables/folders_table.dart';
import 'package:gitopen/infrastructure/persistence/tables/repositories_table.dart';
import 'package:gitopen/infrastructure/persistence/tables/settings_table.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Repositories, Settings, ActivityLog, Folders])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  // A super parameter can't be used here because the positional `e` is also
  // referenced by name in tests; keep the explicit forwarding constructor.
  // ignore: use_super_parameters
  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(activityLog);
      }
      if (from < 3) {
        await m.createTable(folders);
        await m.addColumn(repositories, repositories.parentFolderId);
      }
    },
  );

  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final path = await GitOpenPaths.stateDbPath();
    return NativeDatabase(File(path));
  });
}
