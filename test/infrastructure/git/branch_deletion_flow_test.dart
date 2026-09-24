import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_branch_deletion_inspector.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

void main() {
  test('clean linked worktree and branch are removed together', () async {
    final fixture = await RepoFixture.withLinearHistory(1);
    final parent = await Directory.systemTemp.createTemp('delete-branch-');
    final path = p.join(parent.path, 'linked');
    final repo = RepoLocation(const RepoId('test'), fixture.path, 'test');
    final write = GitCliWriteOperations();
    final flow = BranchDeletionFlow(
      inspector: GitCliBranchDeletionInspector(),
      write: write,
    );
    try {
      await write.addWorktree(repo, path, newBranch: 'linked');
      final status = await flow.inspect(repo, 'linked');
      expect(
        FileSystemEntity.identicalSync(status.worktreePath!, path),
        isTrue,
      );
      expect(status.isMainWorktree, isFalse);
      final results = await flow.deleteMany(repo, [
        const BranchDeleteRequest('linked', removeWorktree: true),
      ]);
      expect(results.single.error, isNull);
      expect(Directory(path).existsSync(), isFalse);
      expect((await flow.inspect(repo, 'linked')).exists, isFalse);
    } finally {
      await fixture.dispose();
      await parent.delete(recursive: true);
    }
  });

  test(
    'dirty linked worktree needs force and main branch is refused',
    () async {
      final fixture = await RepoFixture.withLinearHistory(1);
      final parent = await Directory.systemTemp.createTemp('delete-branch-');
      final path = p.join(parent.path, 'linked');
      final repo = RepoLocation(const RepoId('test'), fixture.path, 'test');
      final write = GitCliWriteOperations();
      final flow = BranchDeletionFlow(
        inspector: GitCliBranchDeletionInspector(),
        write: write,
      );
      try {
        await write.addWorktree(repo, path, newBranch: 'linked');
        await File(p.join(path, 'untracked.txt')).writeAsString('lost');
        expect((await flow.inspect(repo, 'linked')).worktreeDirty, isTrue);
        final refused = await flow.deleteMany(repo, [
          const BranchDeleteRequest('linked', removeWorktree: true),
          const BranchDeleteRequest('master'),
        ]);
        expect(refused[0].error, contains('uncommitted or untracked'));
        expect(refused[1].error, contains('main worktree'));
        expect(Directory(path).existsSync(), isTrue);
        final forced = await flow.deleteMany(repo, [
          const BranchDeleteRequest(
            'linked',
            removeWorktree: true,
            forceWorktree: true,
          ),
        ]);
        expect(forced.single.error, isNull);
      } finally {
        await fixture.dispose();
        await parent.delete(recursive: true);
      }
    },
  );

  test('mixed batch continues after unmerged and current failures', () async {
    final fixture = await RepoFixture.withLinearHistory(1);
    final parent = await Directory.systemTemp.createTemp('delete-branch-');
    final path = p.join(parent.path, 'linked');
    final repo = RepoLocation(const RepoId('test'), fixture.path, 'test');
    final write = GitCliWriteOperations();
    final flow = BranchDeletionFlow(
      inspector: GitCliBranchDeletionInspector(),
      write: write,
    );
    try {
      await write.createBranch(repo, 'merged');
      await write.addWorktree(repo, path, newBranch: 'linked');
      await Process.run('git', [
        'checkout',
        '-q',
        '-b',
        'unmerged',
      ], workingDirectory: path);
      await File(p.join(path, 'new.txt')).writeAsString('new');
      await Process.run('git', ['add', 'new.txt'], workingDirectory: path);
      await Process.run('git', [
        '-c',
        'user.name=Test',
        '-c',
        'user.email=test@example.com',
        'commit',
        '-q',
        '-m',
        'new',
      ], workingDirectory: path);
      final results = await flow.deleteMany(repo, [
        const BranchDeleteRequest('merged'),
        const BranchDeleteRequest('unmerged'),
        const BranchDeleteRequest('linked', removeWorktree: true),
        const BranchDeleteRequest('master'),
      ]);
      expect(results.map((r) => r.error == null), [true, false, true, false]);
      expect(results[1].error, contains('not fully merged'));
      expect(results[3].error, contains('main worktree'));
    } finally {
      await fixture.dispose();
      await parent.delete(recursive: true);
    }
  });

  test('removing worktree can also delete its branch', () async {
    final fixture = await RepoFixture.withLinearHistory(1);
    final parent = await Directory.systemTemp.createTemp('delete-branch-');
    final path = p.join(parent.path, 'linked');
    final repo = RepoLocation(const RepoId('test'), fixture.path, 'test');
    final write = GitCliWriteOperations();
    final flow = BranchDeletionFlow(
      inspector: GitCliBranchDeletionInspector(),
      write: write,
    );
    try {
      await write.addWorktree(repo, path, newBranch: 'linked');
      final result = await flow.removeWorktree(
        repo,
        path,
        deleteBranch: true,
      );
      expect(result.error, isNull);
      expect((await flow.inspect(repo, 'linked')).exists, isFalse);
    } finally {
      await fixture.dispose();
      await parent.delete(recursive: true);
    }
  });

  test(
    'open worktree is protected and server deletes use the callback',
    () async {
      final fixture = await RepoFixture.withLinearHistory(1);
      final parent = await Directory.systemTemp.createTemp('delete-branch-');
      final path = p.join(parent.path, 'linked');
      final main = RepoLocation(const RepoId('test'), fixture.path, 'test');
      final write = GitCliWriteOperations();
      final flow = BranchDeletionFlow(
        inspector: GitCliBranchDeletionInspector(),
        write: write,
      );
      try {
        await write.addWorktree(main, path, newBranch: 'linked');
        final open = RepoLocation(const RepoId('linked'), path, 'linked');
        expect((await flow.inspect(open, 'linked')).isMainWorktree, isTrue);
        expect((await flow.inspectWorktree(open, path))?.isMain, isTrue);
        final remotes = <String>[];
        final results = await flow.deleteMany(
          open,
          [
            const BranchDeleteRequest('linked', removeWorktree: true),
            const BranchDeleteRequest('origin/gone', remote: true),
          ],
          deleteRemote: (ref) async {
            remotes.add(ref);
            return 'denied';
          },
        );
        expect(remotes, ['origin/gone']);
        expect(results.map((r) => r.error), [
          contains('main worktree'),
          'denied',
        ]);
        expect(Directory(path).existsSync(), isTrue);
      } finally {
        await fixture.dispose();
        await parent.delete(recursive: true);
      }
    },
  );
}
