import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/workspaces/repository_validator.dart';
import 'package:gitopen/infrastructure/launcher/io_repository_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  const validator = IoRepositoryValidator();

  test('accepts a worktree and returns one canonical absolute path', () async {
    final root = await Directory.systemTemp.createTemp('gitopen-validator-');
    addTearDown(() => root.delete(recursive: true));
    await Directory(p.join(root.path, '.git')).create();

    final actual = await validator.validate('${root.path}${p.separator}');
    final expected = await root.resolveSymbolicLinks();

    expect(p.isAbsolute(actual), isTrue);
    expect(p.normalize(actual), p.normalize(expected));
  });

  test('accepts a linked-worktree .git file', () async {
    final root = await Directory.systemTemp.createTemp('gitopen-worktree-');
    addTearDown(() => root.delete(recursive: true));
    await File(p.join(root.path, '.git')).writeAsString('gitdir: elsewhere');

    final expected = await root.resolveSymbolicLinks();
    expect(await validator.validate(root.path), p.normalize(expected));
  });

  test('rejects an existing folder that is not a repository', () async {
    final root = await Directory.systemTemp.createTemp('gitopen-plain-');
    addTearDown(() => root.delete(recursive: true));

    expect(
      validator.validate(root.path),
      throwsA(
        isA<RepositoryValidationException>().having(
          (e) => e.kind,
          'kind',
          RepositoryValidationError.notRepository,
        ),
      ),
    );
  });

  test('rejects a missing folder', () {
    final missing = p.join(
      Directory.systemTemp.path,
      'gitopen-missing-${DateTime.now().microsecondsSinceEpoch}',
    );
    expect(
      validator.validate(missing),
      throwsA(
        isA<RepositoryValidationException>().having(
          (e) => e.kind,
          'kind',
          RepositoryValidationError.missing,
        ),
      ),
    );
  });
}
