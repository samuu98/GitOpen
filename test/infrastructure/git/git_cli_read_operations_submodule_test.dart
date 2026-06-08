import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';

import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 't');

  /// Deinitialises the `sub` submodule so its working tree is removed and
  /// `git submodule status` reports it as uninitialized (`-` prefix).
  Future<void> deinit(String repoPath) async {
    final r = await Process.run(
      'git',
      ['submodule', 'deinit', '-f', 'sub'],
      workingDirectory: repoPath,
    );
    if (r.exitCode != 0) {
      throw StateError('deinit failed: ${r.stderr}');
    }
  }

  group('GitCliReadOperations.getSubmodules', () {
    test('returns empty list when the repo has no submodules', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliReadOperations();
        expect(await sut.getSubmodules(loc(f)), isEmpty);
      } finally {
        await f.dispose();
      }
    });

    test('lists the submodule as up-to-date after add', () async {
      final f = await RepoFixture.withSubmodule();
      try {
        final sut = GitCliReadOperations();
        final subs = await sut.getSubmodules(loc(f));

        expect(subs, hasLength(1));
        expect(subs.single.path, 'sub');
        expect(subs.single.status, SubmoduleStatus.upToDate);
        expect(subs.single.sha.value, hasLength(40));
      } finally {
        await f.dispose();
      }
    });

    test('reports uninitialized after deinit', () async {
      final f = await RepoFixture.withSubmodule();
      try {
        await deinit(f.path);
        final sut = GitCliReadOperations();
        final subs = await sut.getSubmodules(loc(f));

        expect(subs, hasLength(1));
        expect(subs.single.path, 'sub');
        expect(subs.single.status, SubmoduleStatus.uninitialized);
      } finally {
        await f.dispose();
      }
    });
  });

  group('GitCliWriteOperations.updateSubmodule', () {
    test('init + update re-initializes a deinitialized submodule', () async {
      final f = await RepoFixture.withSubmodule();
      try {
        await deinit(f.path);
        final read = GitCliReadOperations();
        // Precondition: deinit left it uninitialized.
        expect(
          (await read.getSubmodules(loc(f))).single.status,
          SubmoduleStatus.uninitialized,
        );

        final write = GitCliWriteOperations();
        final res = await write.updateSubmodule(loc(f), 'sub');
        expect(res, isA<GitSuccess<void>>());

        // The submodule's working tree is back and content is present.
        expect(
          File('${f.path}${Platform.pathSeparator}sub'
                  '${Platform.pathSeparator}inner.txt')
              .existsSync(),
          isTrue,
        );
        expect(
          (await read.getSubmodules(loc(f))).single.status,
          SubmoduleStatus.upToDate,
        );
      } finally {
        await f.dispose();
      }
    });

    test('updateAllSubmodules with init re-initializes all submodules',
        () async {
      final f = await RepoFixture.withSubmodule();
      try {
        await deinit(f.path);
        final write = GitCliWriteOperations();
        final res = await write.updateAllSubmodules(loc(f));
        expect(res, isA<GitSuccess<void>>());

        final read = GitCliReadOperations();
        expect(
          (await read.getSubmodules(loc(f))).single.status,
          SubmoduleStatus.upToDate,
        );
      } finally {
        await f.dispose();
      }
    });
  });
}
