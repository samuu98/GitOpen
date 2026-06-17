import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';

void main() {
  group('FolderId', () {
    test('newId generates a 32-char hex string', () {
      final id = FolderId.newId();
      expect(id.value, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id.value), isTrue);
    });

    test('equality is by value', () {
      expect(const FolderId('a'), const FolderId('a'));
      expect(const FolderId('a'), isNot(const FolderId('b')));
    });
  });

  group('Folder', () {
    test('copyWith replaces only the given fields', () {
      const f = Folder(
        id: FolderId('f1'),
        name: 'Work',
        parentId: null,
        sortOrder: 0,
        collapsed: false,
      );
      final renamed = f.copyWith(name: 'Personal', collapsed: true);
      expect(renamed.name, 'Personal');
      expect(renamed.collapsed, isTrue);
      expect(renamed.id, const FolderId('f1'));
      expect(renamed.sortOrder, 0);
    });

    test('equality is structural', () {
      const a = Folder(
        id: FolderId('f1'),
        name: 'Work',
        parentId: null,
        sortOrder: 0,
        collapsed: false,
      );
      const b = Folder(
        id: FolderId('f1'),
        name: 'Work',
        parentId: null,
        sortOrder: 0,
        collapsed: false,
      );
      expect(a, b);
    });
  });
}
