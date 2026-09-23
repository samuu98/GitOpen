import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/files/file_tree_entry.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) =>
      RepoLocation(RepoId.newId(), f.path, 'test');

  group('GitCliReadOperations.getFileTree', () {
    test('lists root files for commit', () async {
      final f = await RepoFixture.withLinearHistory(3);
      try {
        final sut = GitCliReadOperations();
        final entries = await sut.getFileTree(loc(f), CommitSha(f.headSha), '');
        final names = entries.map((e) => e.name).toSet();
        expect(names, containsAll(['file_0.txt', 'file_1.txt', 'file_2.txt']));
        expect(entries.first.kind, FileTreeKind.blob);
      } finally {
        await f.dispose();
      }
    });

    test('recursive: true lists every blob with its full path', () async {
      final f = await RepoFixture.empty();
      try {
        await File(p.join(f.path, 'root.txt')).writeAsString('r\n');
        final nested = Directory(p.join(f.path, 'dir', 'sub'))
          ..createSync(recursive: true);
        await File(p.join(nested.path, 'deep.txt')).writeAsString('d\n');
        await Process.run('git', ['add', '-A'], workingDirectory: f.path);
        await Process.run(
          'git',
          ['commit', '-q', '-m', 'tree'],
          workingDirectory: f.path,
        );
        final head = await Process.run(
          'git',
          ['rev-parse', 'HEAD'],
          workingDirectory: f.path,
        );
        final sha = CommitSha((head.stdout as String).trim());

        final sut = GitCliReadOperations();
        final entries = await sut.getFileTree(loc(f), sha, '', recursive: true);

        final paths = entries.map((e) => e.fullPath).toList()..sort();
        expect(paths, ['dir/sub/deep.txt', 'root.txt']);
        // -r lists blobs only — no tree rows.
        expect(entries.any((e) => e.kind == FileTreeKind.tree), isFalse);
        expect(
          entries.firstWhere((e) => e.fullPath == 'dir/sub/deep.txt').name,
          'deep.txt',
        );
      } finally {
        await f.dispose();
      }
    });

    test('returns UTF-8 and spaced paths without Git quoting', () async {
      final f = await RepoFixture.empty();
      try {
        for (final name in ['café.txt', 'with space.txt']) {
          await File(p.join(f.path, name)).writeAsString(name);
        }
        await Process.run('git', ['add', '-A'], workingDirectory: f.path);
        await Process.run('git', [
          'commit',
          '-qm',
          'paths',
        ], workingDirectory: f.path);
        final head = await Process.run('git', [
          'rev-parse',
          'HEAD',
        ], workingDirectory: f.path);
        final entries = await GitCliReadOperations().getFileTree(
          loc(f),
          CommitSha((head.stdout as String).trim()),
          '',
        );
        expect(
          entries.map((e) => e.fullPath),
          containsAll(['café.txt', 'with space.txt']),
        );
      } finally {
        await f.dispose();
      }
    });
  });
}
