import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'repo_fixture.dart';

void main() {
  group('RepoFixture', () {
    test('withLinearHistory creates n commits', () async {
      final f = await RepoFixture.withLinearHistory(5);
      try {
        final r = await Process.run('git', ['rev-list', '--count', 'HEAD'],
            workingDirectory: f.path);
        expect(r.exitCode, 0);
        expect(r.stdout.toString().trim(), '5');
        expect(f.headSha, isNotEmpty);
      } finally {
        await f.dispose();
      }
    });

    test('empty creates an initialised repo with no commits', () async {
      final f = await RepoFixture.empty();
      try {
        expect(Directory(p.join(f.path, '.git')).existsSync(), isTrue);
        final r = await Process.run(
            'git', ['rev-list', '--count', '--all'],
            workingDirectory: f.path);
        expect(r.stdout.toString().trim(), '0');
      } finally {
        await f.dispose();
      }
    });

    test('withBranches creates master and feature', () async {
      final f = await RepoFixture.withBranches();
      try {
        final r = await Process.run('git', ['branch', '--list'],
            workingDirectory: f.path);
        expect(r.stdout.toString(), contains('feature'));
        expect(r.stdout.toString(), contains('master'));
      } finally {
        await f.dispose();
      }
    });

    test('copy preserves history and isolates working-tree changes', () async {
      final original = await RepoFixture.withRebaseHistory();
      try {
        final copied = await original.copy();
        try {
          expect(copied.rebaseShas, original.rebaseShas);
          expect(copied.headSha, original.headSha);
          await File(p.join(copied.path, 'c3.txt')).writeAsString('changed\n');
          expect(
            await File(p.join(original.path, 'c3.txt')).readAsString(),
            'c3\n',
          );
          final status = await Process.run('git', ['status', '--short'],
              workingDirectory: copied.path);
          expect(status.exitCode, 0);
          expect(status.stdout.toString(), contains('c3.txt'));
        } finally {
          await copied.dispose();
        }
      } finally {
        await original.dispose();
      }
    });

    test('submodule source is removed with its owning fixture', () async {
      final fixture = await RepoFixture.withSubmodule();
      final sourcePath = fixture.submoduleSourcePath;
      expect(Directory(sourcePath).existsSync(), isTrue);
      await fixture.dispose();
      expect(Directory(sourcePath).existsSync(), isFalse);
    });
  });
}
