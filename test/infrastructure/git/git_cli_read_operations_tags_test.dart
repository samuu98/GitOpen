import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 'test');

  group('GitCliReadOperations.getTags', () {
    test('returns tags on multiple commits, both annotated and lightweight', () async {
      final f = await RepoFixture.withLinearHistory(3);
      try {
        // Tag the oldest commit with an annotated tag.
        await Process.run('git', ['tag', '-a', 'v1.0', '-m', 'first', 'HEAD~2'],
            workingDirectory: f.path);
        // Tag the middle commit with a lightweight tag.
        await Process.run('git', ['tag', 'v1.1', 'HEAD~1'],
            workingDirectory: f.path);
        // Tag HEAD with another annotated.
        await Process.run('git', ['tag', '-a', 'v1.2', '-m', 'latest', 'HEAD'],
            workingDirectory: f.path);

        final sut = GitCliReadOperations();
        final tags = await sut.getTags(loc(f));

        expect(tags.length, 3, reason: 'should find all three tags');

        // Each tag should point to a DIFFERENT sha.
        final shas = tags.map((t) => t.targetSha.value).toSet();
        expect(shas.length, 3, reason: 'three distinct target shas');

        // Annotated detection must work for v1.0 and v1.2.
        final v10 = tags.firstWhere((t) => t.name == 'v1.0');
        final v11 = tags.firstWhere((t) => t.name == 'v1.1');
        final v12 = tags.firstWhere((t) => t.name == 'v1.2');
        expect(v10.isAnnotated, isTrue);
        expect(v11.isAnnotated, isFalse);
        expect(v12.isAnnotated, isTrue);
      } finally {
        await f.dispose();
      }
    });
  });
}
