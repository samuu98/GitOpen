import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'tables/repositories_table.dart';
import 'tables/settings_table.dart';
import 'path_provider_helper.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Repositories, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  // ignore: use_super_parameters
  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;

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
