import 'package:drift/drift.dart';

class Repositories extends Table {
  TextColumn get id => text().withLength(min: 32, max: 32)();
  TextColumn get path => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get color => text().nullable()();
  DateTimeColumn get lastOpenedUtc => dateTime()();
  // Order within this repo's parent folder (shared with sibling folders).
  // Historically named "tabOrder"; kept to avoid a column rename migration.
  IntColumn get tabOrder => integer()();
  // Null parentFolderId == root-level repo.
  TextColumn get parentFolderId => text().nullable()();
  DateTimeColumn get createdUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
