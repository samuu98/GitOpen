import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('preview and conflict merge return an unquoted path', () async {
    final f = await RepoFixture.empty();
    try {
      final file = File(p.join(f.path, 'café.txt'));
      await file.writeAsString('base\n');
      await Process.run('git', ['add', '-A'], workingDirectory: f.path);
      await Process.run('git', ['commit', '-qm', 'base'],
          workingDirectory: f.path);
      await Process.run('git', ['checkout', '-qb', 'feature'],
          workingDirectory: f.path);
      await file.writeAsString('feature\n');
      await Process.run('git', ['commit', '-qam', 'feature'],
          workingDirectory: f.path);
      await Process.run('git', ['checkout', '-q', 'master'],
          workingDirectory: f.path);
      await file.writeAsString('master\n');
      await Process.run('git', ['commit', '-qam', 'master'],
          workingDirectory: f.path);
      final repo = RepoLocation(RepoId.newId(), f.path, 't');
      final sut = GitCliWriteOperations();
      final preview = await sut.previewMerge(repo, 'feature');
      expect(preview, isA<GitSuccess<MergePreview>>());
      expect((preview as GitSuccess<MergePreview>).value,
          isA<MergePreviewConflicts>());
      expect((preview.value as MergePreviewConflicts).conflictedPaths,
          ['café.txt']);
      final merged = await sut.merge(repo, 'feature');
      expect(merged, isA<GitSuccess<MergeOutcome>>());
      expect((merged as GitSuccess<MergeOutcome>).value, isA<MergeConflict>());
      expect((merged.value as MergeConflict).conflictedPaths, ['café.txt']);
    } finally {
      await f.dispose();
    }
  });

  test('clean divergent merge completes without opening an editor', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      await Process.run('git', [
        'config',
        'core.editor',
        'false',
      ], workingDirectory: f.path);
      await Process.run('git', [
        'checkout',
        '-qb',
        'feature',
      ], workingDirectory: f.path);
      await File(p.join(f.path, 'feature.txt')).writeAsString('feature\n');
      await Process.run('git', ['add', '-A'], workingDirectory: f.path);
      await Process.run('git', [
        'commit',
        '-qm',
        'feature',
      ], workingDirectory: f.path);
      await Process.run('git', [
        'checkout',
        '-q',
        'master',
      ], workingDirectory: f.path);
      await File(p.join(f.path, 'master.txt')).writeAsString('master\n');
      await Process.run('git', ['add', '-A'], workingDirectory: f.path);
      await Process.run('git', [
        'commit',
        '-qm',
        'master',
      ], workingDirectory: f.path);
      final result = await GitCliWriteOperations()
          .merge(RepoLocation(RepoId.newId(), f.path, 't'), 'feature')
          .timeout(const Duration(seconds: 10));
      expect(result, isA<GitSuccess<MergeOutcome>>());
      expect((result as GitSuccess<MergeOutcome>).value, isA<MergeMerged>());
    } finally {
      await f.dispose();
    }
  });

  test('ff merge', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      await Process.run(
        'git',
        ['checkout', '-b', 'feature'],
        workingDirectory: f.path,
      );
      File(p.join(f.path, 'new.txt')).writeAsStringSync('hi');
      await Process.run('git', ['add', '.'], workingDirectory: f.path);
      await Process.run(
        'git',
        ['commit', '-m', 'fea'],
        workingDirectory: f.path,
      );
      await Process.run(
        'git',
        ['checkout', 'master'],
        workingDirectory: f.path,
      );
      final sut = GitCliWriteOperations();
      final res = await sut.merge(
        RepoLocation(RepoId.newId(), f.path, 't'),
        'feature',
      );
      expect(res, isA<GitSuccess<MergeOutcome>>());
      expect(
        (res as GitSuccess<MergeOutcome>).value,
        isA<MergeFastForward>(),
      );
    } finally {
      await f.dispose();
    }
  });

  test('3-way merge with conflict reports conflicted paths', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      // create branch and modify file
      await Process.run(
        'git',
        ['checkout', '-b', 'feature'],
        workingDirectory: f.path,
      );
      File(p.join(f.path, 'file_0.txt')).writeAsStringSync('branch version\n');
      await Process.run(
        'git',
        ['commit', '-am', 'branch'],
        workingDirectory: f.path,
      );
      // back to master, modify same line
      await Process.run(
        'git',
        ['checkout', 'master'],
        workingDirectory: f.path,
      );
      File(p.join(f.path, 'file_0.txt')).writeAsStringSync('master version\n');
      await Process.run(
        'git',
        ['commit', '-am', 'master'],
        workingDirectory: f.path,
      );
      final sut = GitCliWriteOperations();
      final res = await sut.merge(
        RepoLocation(RepoId.newId(), f.path, 't'),
        'feature',
      );
      expect(res, isA<GitSuccess<MergeOutcome>>());
      final outcome = (res as GitSuccess<MergeOutcome>).value;
      expect(outcome, isA<MergeConflict>());
      expect(
        (outcome as MergeConflict).conflictedPaths,
        contains('file_0.txt'),
      );
    } finally {
      await f.dispose();
    }
  });
}
