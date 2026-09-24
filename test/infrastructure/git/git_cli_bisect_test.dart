import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:gitopen/infrastructure/git/io_git_dir_probe.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

Future<String> git(String cwd, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${result.stderr}');
  }
  return result.stdout.toString().trim();
}

void main() {
  test('bisect skip, good/bad, found, and reset restore branch', () async {
    final fixture = await RepoFixture.withLinearHistory(9);
    final repo = RepoLocation(RepoId.newId(), fixture.path, 'bisect');
    final writer = GitCliWriteOperations();
    final reader = GitCliReadOperations();
    try {
      final shas = <String>[];
      for (var i = 8; i >= 0; i--) {
        shas.add(await git(fixture.path, ['rev-parse', 'HEAD~$i']));
      }
      expect(
        await writer.bisectStart(repo, fixture.headSha, shas[0]),
        isA<GitSuccess<void>>(),
      );
      expect(const IoGitDirProbe().fileExists(repo, 'BISECT_LOG'), isTrue);
      final container = ProviderContainer();
      try {
        expect(
          await container.read(repoStateProvider(repo).future),
          InProgressOp.bisect,
        );
      } finally {
        container.dispose();
      }
      final initial = await reader.getBisectState(repo);
      expect(initial, isNotNull);
      expect(initial!.bad.value, fixture.headSha);
      expect(initial.good.map((sha) => sha.value), contains(shas[0]));
      expect(initial.stepsLeft, greaterThan(0));
      expect(initial.subject, isNotEmpty);

      expect(await writer.bisectSkip(repo), isA<GitSuccess<void>>());
      expect(
        (await reader.getBisectState(repo))!.candidate,
        isNot(initial.candidate),
      );
      expect(await writer.bisectReset(repo), isA<GitSuccess<void>>());
      expect(
        await git(fixture.path, ['symbolic-ref', '--short', 'HEAD']),
        'master',
      );
      expect(await git(fixture.path, ['rev-parse', 'HEAD']), fixture.headSha);

      expect(
        await writer.bisectStart(repo, fixture.headSha, shas[0]),
        isA<GitSuccess<void>>(),
      );
      for (var step = 0; step < 8; step++) {
        final state = (await reader.getBisectState(repo))!;
        if (state.firstBad != null) {
          expect(state.firstBad!.value, shas[5]);
          break;
        }
        final index = shas.indexOf(state.candidate.value);
        expect(index, greaterThan(0));
        final result = index >= 5
            ? await writer.bisectBad(repo)
            : await writer.bisectGood(repo);
        expect(result, isA<GitSuccess<void>>());
      }
      final found = (await reader.getBisectState(repo))!;
      expect(found.firstBad?.value, shas[5]);
      expect(found.bad.value, shas[5]);
      expect(await writer.bisectReset(repo), isA<GitSuccess<void>>());
      expect(await reader.getBisectState(repo), isNull);
      expect(
        await git(fixture.path, ['symbolic-ref', '--short', 'HEAD']),
        'master',
      );
      expect(await git(fixture.path, ['rev-parse', 'HEAD']), fixture.headSha);
    } finally {
      await fixture.dispose();
    }
  });

  test('dirty worktree blocks bisect start with git error', () async {
    final fixture = await RepoFixture.withLinearHistory(3);
    final repo = RepoLocation(RepoId.newId(), fixture.path, 'dirty');
    try {
      final good = await git(fixture.path, ['rev-parse', 'HEAD~2']);
      File(p.join(fixture.path, 'file_2.txt')).writeAsStringSync('dirty\n');
      final result = await GitCliWriteOperations().bisectStart(
        repo,
        fixture.headSha,
        good,
      );
      expect(result, isA<GitFailure<void>>());
      expect((result as GitFailure<void>).message, isNotEmpty);
      expect(await GitCliReadOperations().getBisectState(repo), isNull);
    } finally {
      await fixture.dispose();
    }
  });

  test('linked worktree resolves bisect markers in its gitdir', () async {
    final fixture = await RepoFixture.withLinearHistory(5);
    final linked = p.join(fixture.path, 'linked');
    try {
      await git(fixture.path, ['worktree', 'add', '-qb', 'linked', linked]);
      final repo = RepoLocation(RepoId.newId(), linked, 'linked');
      final good = await git(linked, ['rev-parse', 'HEAD~4']);
      final start = await GitCliWriteOperations().bisectStart(
        repo,
        fixture.headSha,
        good,
      );
      expect(start, isA<GitSuccess<void>>());
      expect(File(p.join(linked, '.git')).existsSync(), isTrue);
      expect(const IoGitDirProbe().fileExists(repo, 'BISECT_LOG'), isTrue);
      final container = ProviderContainer();
      try {
        expect(
          await container.read(repoStateProvider(repo).future),
          InProgressOp.bisect,
        );
      } finally {
        container.dispose();
      }
      expect(await GitCliReadOperations().getBisectState(repo), isNotNull);
      expect(
        await GitCliWriteOperations().bisectReset(repo),
        isA<GitSuccess<void>>(),
      );
      expect(await git(linked, ['symbolic-ref', '--short', 'HEAD']), 'linked');
    } finally {
      await fixture.dispose();
    }
  });
}
