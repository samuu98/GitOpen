import 'package:drift/drift.dart';

// Renamed so the generated row class does not collide with the domain
// `Folder` type (table `Folders` would otherwise generate `Folder`).
@DataClassName('FolderRow')
class Folders extends Table {
  TextColumn get id => text().withLength(min: 32, max: 32)();
  TextColumn get name => text()();
  // Null parentId == root-level folder.
  TextColumn get parentId => text().nullable()();
  // Order within the parent's shared (folders + repos) sort space.
  IntColumn get sortOrder => integer()();
  BoolColumn get collapsed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
