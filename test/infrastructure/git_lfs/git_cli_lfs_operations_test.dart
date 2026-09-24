import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git_lfs/git_cli_lfs_operations.dart';

void main() {
  test('cancelling LFS progress kills the process', () async {
    final process = _FakeProcess();
    addTearDown(process.dispose);
    final started = Completer<void>();
    final received = Completer<void>();
    final sut = GitCliLfsOperations(
      startProcess: (executable, args, cwd, environment) async {
        started.complete();
        return process;
      },
    );
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    final subscription = sut.fetch(repo).listen((_) => received.complete());

    await started.future.timeout(const Duration(seconds: 5));
    process.output.add(utf8.encode('Downloading\n'));
    await received.future.timeout(const Duration(seconds: 5));
    await subscription.cancel().timeout(const Duration(seconds: 5));

    expect(process.killed, isTrue);
  });

  test('track and untrack pattern when git lfs is available', () async {
    final version = await Process.run('git', ['lfs', 'version']);
    if (version.exitCode != 0) {
      markTestSkipped('git lfs is not installed');
      return;
    }

    // A bare `git init` keeps the spawn count low: under a loaded suite each
    // extra fixture step (config, initial commit) pushed this past its timeout.
    final fixture = await Directory.systemTemp.createTemp('gitopen-lfs-test-');
    addTearDown(() => fixture.delete(recursive: true));
    final init = await Process.run('git', [
      'init',
      '-q',
    ], workingDirectory: fixture.path);
    expect(init.exitCode, 0, reason: init.stderr.toString());
    final repo = RepoLocation(RepoId.newId(), fixture.path, 'repo');
    final sut = GitCliLfsOperations();

    await sut.track(repo, '*.bin');
    expect((await sut.trackedPatterns(repo)).single.pattern, '*.bin');
    await sut.untrack(repo, '*.bin');
    expect(await sut.trackedPatterns(repo), isEmpty);
  });
}

final class _FakeProcess implements Process {
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  final exit = Completer<int>();
  bool killed = false;

  @override
  Stream<List<int>> get stdout => output.stream;

  @override
  Stream<List<int>> get stderr => errors.stream;

  @override
  Future<int> get exitCode => exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!exit.isCompleted) exit.complete(-1);
    return true;
  }

  Future<void> dispose() async {
    if (!exit.isCompleted) exit.complete(-1);
    await output.close();
    await errors.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
