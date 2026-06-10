import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';

import '../../_helpers/repo_fixture.dart';

void main() {
  test('createTag', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      final sut = GitCliWriteOperations();
      final res = await sut.createTag(
        RepoLocation(RepoId.newId(), f.path, 't'),
        'v1.0',
      );
      expect(res, isA<GitSuccess<void>>());
      final out = await Process.run(
        'git',
        ['tag', '--list'],
        workingDirectory: f.path,
      );
      expect(out.stdout.toString(), contains('v1.0'));
    } finally { await f.dispose(); }
  });

  test('createTag with message creates an annotated tag', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      final sut = GitCliWriteOperations();
      final res = await sut.createTag(
        RepoLocation(RepoId.newId(), f.path, 't'),
        'v9.9.9',
        message: 'release notes',
      );
      expect(res, isA<GitSuccess<void>>());
      final type = await Process.run(
        'git',
        ['cat-file', '-t', 'v9.9.9'],
        workingDirectory: f.path,
      );
      // An annotated tag is its own 'tag' object; lightweight would be
      // 'commit'.
      expect(type.stdout.toString().trim(), 'tag');
    } finally { await f.dispose(); }
  });

  test('deleteTag', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      await Process.run('git', ['tag', 'v0.1'], workingDirectory: f.path);
      final sut = GitCliWriteOperations();
      final res = await sut.deleteTag(
        RepoLocation(RepoId.newId(), f.path, 't'),
        'v0.1',
      );
      expect(res, isA<GitSuccess<void>>());
    } finally { await f.dispose(); }
  });
}
