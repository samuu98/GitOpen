import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('clone from local source repo', () async {
    final src = await RepoFixture.withLinearHistory(2);
    final dest = p.join(Directory.systemTemp.path, 'gitopen-clonetest-${DateTime.now().millisecondsSinceEpoch}');
    try {
      final sut = GitCliWriteOperations();
      await sut.clone(src.path, dest).toList();
      expect(Directory(p.join(dest, '.git')).existsSync(), isTrue);
    } finally {
      await src.dispose();
      try { Directory(dest).deleteSync(recursive: true); } catch (_) {}
    }
  });
}
