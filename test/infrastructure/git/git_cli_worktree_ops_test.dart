import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

RepoLocation loc(RepoFixture f) => RepoLocation(const RepoId('t'), f.path, 't');

void main() {
  group('worktree operations', () {
    test('getWorktrees lists the main worktree first', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final read = GitCliReadOperations();
        final trees = await read.getWorktrees(loc(f));
        expect(trees, hasLength(1));
        expect(trees.first.branch, 'master');
        expect(trees.first.headSha?.value, f.headSha);
      } finally {
        await f.dispose();
      }
    });

    test('addWorktree on a new branch shows up in the list; remove drops it',
        () async {
      final f = await RepoFixture.withLinearHistory(2);
      final wtPath =
          p.join(Directory.systemTemp.createTempSync('gitopen-wt-').path, 'w1');
      try {
        final read = GitCliReadOperations();
        final write = GitCliWriteOperations();

        final added = await write.addWorktree(
          loc(f),
          wtPath,
          newBranch: 'wt-feature',
        );
        expect(added, isA<GitSuccess<void>>());

        var trees = await read.getWorktrees(loc(f));
        expect(trees, hasLength(2));
        expect(trees.any((w) => w.branch == 'wt-feature'), isTrue);

        final removed = await write.removeWorktree(loc(f), wtPath);
        expect(removed, isA<GitSuccess<void>>());

        trees = await read.getWorktrees(loc(f));
        expect(trees, hasLength(1));
      } finally {
        await f.dispose();
      }
    });

    test('addWorktree fails cleanly when the branch is already checked out',
        () async {
      final f = await RepoFixture.withLinearHistory(1);
      final wtPath =
          p.join(Directory.systemTemp.createTempSync('gitopen-wt-').path, 'w2');
      try {
        final write = GitCliWriteOperations();
        // 'master' is checked out in the main worktree already.
        final result = await write.addWorktree(loc(f), wtPath, ref: 'master');
        expect(result, isA<GitFailure<void>>());
      } finally {
        await f.dispose();
      }
    });
  });
}
