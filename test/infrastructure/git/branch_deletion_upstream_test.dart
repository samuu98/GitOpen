import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_branch_deletion_inspector.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

/// `git branch -d` checks the branch against its upstream when it has one, and
/// against HEAD otherwise. These fixtures pin the dialog's classification to
/// that rule, so a worktree is never removed for a branch git then refuses.
Future<void> _git(String cwd, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    fail('git ${args.join(' ')} in $cwd failed: ${result.stderr}');
  }
}

Future<void> _commit(String cwd, String file) async {
  await File(p.join(cwd, file)).writeAsString('$file\n');
  await _git(cwd, ['add', file]);
  await _git(cwd, ['commit', '-q', '-m', 'add $file']);
}

class _Sandbox {
  _Sandbox(this.fixture, this.parent, this.repo, this.flow);

  final RepoFixture fixture;
  final Directory parent;
  final RepoLocation repo;
  final BranchDeletionFlow flow;

  String pathFor(String name) => p.join(parent.path, name);

  Future<bool> branchExists(String name) async =>
      (await flow.inspect(repo, name)).exists;

  Future<void> dispose() async {
    await fixture.dispose();
    if (parent.existsSync()) await parent.delete(recursive: true);
  }
}

Future<_Sandbox> _sandbox() async {
  final fixture = await RepoFixture.withLinearHistory(1);
  final parent = await Directory.systemTemp.createTemp('branch-upstream-');
  final remote = p.join(parent.path, 'remote.git');
  await _git(fixture.path, ['init', '-q', '--bare', remote]);
  await _git(fixture.path, ['remote', 'add', 'origin', remote]);
  await _git(fixture.path, ['push', '-q', 'origin', 'master']);
  return _Sandbox(
    fixture,
    parent,
    RepoLocation(const RepoId('test'), fixture.path, 'test'),
    BranchDeletionFlow(
      inspector: GitCliBranchDeletionInspector(),
      write: GitCliWriteOperations(),
    ),
  );
}

/// `linked` is pushed, then gains one commit master fast-forwards to: it is
/// merged into HEAD but *not* into `origin/linked`, which is exactly what
/// `git branch -d` refuses.
Future<String> _linkedAheadOfUpstream(_Sandbox s) async {
  final path = s.pathFor('linked');
  await _git(s.fixture.path, ['worktree', 'add', '-q', '-b', 'linked', path]);
  await _commit(path, 'b.txt');
  await _git(path, ['push', '-q', '-u', 'origin', 'linked']);
  await _commit(path, 'c.txt');
  await _git(s.fixture.path, ['merge', '-q', '--ff-only', 'linked']);
  return path;
}

void main() {
  test('merged into HEAD without an upstream deletes both sides', () async {
    final s = await _sandbox();
    final path = s.pathFor('plain');
    try {
      await _git(s.fixture.path, [
        'worktree',
        'add',
        '-q',
        '-b',
        'plain',
        path,
      ]);
      await _commit(path, 'b.txt');
      await _git(s.fixture.path, ['merge', '-q', '--ff-only', 'plain']);
      expect((await s.flow.inspect(s.repo, 'plain')).merged, isTrue);
      final results = await s.flow.deleteMany(s.repo, [
        const BranchDeleteRequest('plain', removeWorktree: true),
      ]);
      expect(results.single.error, isNull);
      expect(Directory(path).existsSync(), isFalse);
      expect(await s.branchExists('plain'), isFalse);
    } finally {
      await s.dispose();
    }
  });

  test('merged into its upstream but not HEAD needs no force', () async {
    final s = await _sandbox();
    final path = s.pathFor('up');
    try {
      await _git(s.fixture.path, ['worktree', 'add', '-q', '-b', 'up', path]);
      await _commit(path, 'b.txt');
      await _git(path, ['push', '-q', '-u', 'origin', 'up']);
      expect((await s.flow.inspect(s.repo, 'up')).merged, isTrue);
      final results = await s.flow.deleteMany(s.repo, [
        const BranchDeleteRequest('up', removeWorktree: true),
      ]);
      expect(results.single.error, isNull);
      expect(Directory(path).existsSync(), isFalse);
      expect(await s.branchExists('up'), isFalse);
    } finally {
      await s.dispose();
    }
  });

  test('unmerged against its upstream removes nothing without force', () async {
    final s = await _sandbox();
    try {
      final path = await _linkedAheadOfUpstream(s);
      expect((await s.flow.inspect(s.repo, 'linked')).merged, isFalse);
      final results = await s.flow.deleteMany(s.repo, [
        const BranchDeleteRequest('linked', removeWorktree: true),
      ]);
      expect(results.single.needsForce, isTrue);
      expect(results.single.error, contains('Enable force delete'));
      expect(
        Directory(path).existsSync(),
        isTrue,
        reason: 'the worktree must survive a branch git would refuse',
      );
      expect(await s.branchExists('linked'), isTrue);
    } finally {
      await s.dispose();
    }
  });

  test('unmerged against its upstream is removed with force', () async {
    final s = await _sandbox();
    try {
      final path = await _linkedAheadOfUpstream(s);
      final results = await s.flow.deleteMany(s.repo, [
        const BranchDeleteRequest(
          'linked',
          forceBranch: true,
          removeWorktree: true,
        ),
      ]);
      expect(results.single.error, isNull);
      expect(Directory(path).existsSync(), isFalse);
      expect(await s.branchExists('linked'), isFalse);
    } finally {
      await s.dispose();
    }
  });

  test('worktree removal deletes a branch merged into HEAD', () async {
    final s = await _sandbox();
    final path = s.pathFor('plain');
    try {
      await _git(s.fixture.path, [
        'worktree',
        'add',
        '-q',
        '-b',
        'plain',
        path,
      ]);
      await _commit(path, 'b.txt');
      await _git(s.fixture.path, ['merge', '-q', '--ff-only', 'plain']);
      final result = await s.flow.removeWorktree(
        s.repo,
        path,
        deleteBranch: true,
      );
      expect(result.error, isNull);
      expect(Directory(path).existsSync(), isFalse);
      expect(await s.branchExists('plain'), isFalse);
    } finally {
      await s.dispose();
    }
  });

  test('worktree removal deletes a branch merged into its upstream', () async {
    final s = await _sandbox();
    final path = s.pathFor('up');
    try {
      await _git(s.fixture.path, ['worktree', 'add', '-q', '-b', 'up', path]);
      await _commit(path, 'b.txt');
      await _git(path, ['push', '-q', '-u', 'origin', 'up']);
      final result = await s.flow.removeWorktree(
        s.repo,
        path,
        deleteBranch: true,
      );
      expect(result.error, isNull);
      expect(Directory(path).existsSync(), isFalse);
      expect(await s.branchExists('up'), isFalse);
    } finally {
      await s.dispose();
    }
  });

  test('worktree removal keeps an unmerged branch without force', () async {
    final s = await _sandbox();
    try {
      final path = await _linkedAheadOfUpstream(s);
      final result = await s.flow.removeWorktree(
        s.repo,
        path,
        deleteBranch: true,
      );
      expect(result.needsForce, isTrue);
      expect(result.error, contains('Enable force delete'));
      expect(Directory(path).existsSync(), isTrue);
      expect(await s.branchExists('linked'), isTrue);
    } finally {
      await s.dispose();
    }
  });

  test('worktree removal deletes an unmerged branch with force', () async {
    final s = await _sandbox();
    try {
      final path = await _linkedAheadOfUpstream(s);
      final result = await s.flow.removeWorktree(
        s.repo,
        path,
        deleteBranch: true,
        forceBranch: true,
      );
      expect(result.error, isNull);
      expect(Directory(path).existsSync(), isFalse);
      expect(await s.branchExists('linked'), isFalse);
    } finally {
      await s.dispose();
    }
  });
}
