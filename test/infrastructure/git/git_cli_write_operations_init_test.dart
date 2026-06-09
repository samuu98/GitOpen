import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;

void main() {
  group('GitCliWriteOperations.initRepo', () {
    test('initialises a repository in an empty directory', () async {
      final dir = Directory.systemTemp.createTempSync('gitopen-init-');
      try {
        final sut = GitCliWriteOperations();
        final result = await sut.initRepo(dir.path);
        expect(result, isA<GitSuccess<void>>());
        expect(Directory(p.join(dir.path, '.git')).existsSync(), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('fails with a classified GitFailure when the target is a file',
        () async {
      final dir = Directory.systemTemp.createTempSync('gitopen-init-');
      try {
        final blocker = File(p.join(dir.path, 'not-a-dir'));
        await blocker.writeAsString('x');
        final sut = GitCliWriteOperations();
        final result = await sut.initRepo(blocker.path);
        expect(result, isA<GitFailure<void>>());
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
