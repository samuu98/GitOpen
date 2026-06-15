import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/watch/io_repo_watcher.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

void main() {
  test(
    'emits when .git/HEAD changes',
    () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final watcher = IoRepoWatcher();
        final repo = RepoLocation(RepoId.newId(), f.path, 't');
        final first = watcher.changes(repo).first;
        // Give the OS watcher a beat to attach before mutating.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await File(
          p.join(f.path, '.git', 'HEAD'),
        ).writeAsString('ref: refs/heads/master\n');
        await first.timeout(const Duration(seconds: 10));
      } finally {
        await f.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('stream closes (no error) for a non-git directory', () async {
    final dir = Directory.systemTemp.createTempSync('gitopen-nowatch-');
    try {
      final watcher = IoRepoWatcher();
      final repo = RepoLocation(RepoId.newId(), dir.path, 't');
      final events = await watcher.changes(repo).toList();
      expect(events, isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  group('isTransientGitNoise', () {
    test('ignores the index and any lock file', () {
      expect(isTransientGitNoise(p.join('r', '.git', 'index')), isTrue);
      expect(isTransientGitNoise(p.join('r', '.git', 'index.lock')), isTrue);
      expect(isTransientGitNoise(p.join('r', '.git', 'HEAD.lock')), isTrue);
      expect(isTransientGitNoise(p.join('r', '.git', 'config.lock')), isTrue);
      expect(
        isTransientGitNoise(p.join('r', '.git', 'packed-refs.lock')),
        isTrue,
      );
    });

    test('keeps meaningful bookkeeping files', () {
      expect(isTransientGitNoise(p.join('r', '.git', 'HEAD')), isFalse);
      expect(isTransientGitNoise(p.join('r', '.git', 'ORIG_HEAD')), isFalse);
      expect(isTransientGitNoise(p.join('r', '.git', 'FETCH_HEAD')), isFalse);
      expect(isTransientGitNoise(p.join('r', '.git', 'MERGE_HEAD')), isFalse);
      expect(isTransientGitNoise(p.join('r', '.git', 'packed-refs')), isFalse);
      expect(
        isTransientGitNoise(p.join('r', '.git', 'logs', 'HEAD')),
        isFalse,
      );
    });
  });
}
