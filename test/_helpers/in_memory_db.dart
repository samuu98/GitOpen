import 'package:drift/native.dart';
import 'package:gitopen/infrastructure/persistence/database.dart';

AppDatabase newInMemoryDb() => AppDatabase.forTesting(NativeDatabase.memory());
