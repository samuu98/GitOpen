import 'package:drift/drift.dart';

class ActivityLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get opId => text()();
  TextColumn get kind => text()();
  TextColumn get label => text()();
  TextColumn get repoId => text().nullable()();
  TextColumn get status => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  TextColumn get stderr => text().nullable()();
  TextColumn get errorMessage => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
