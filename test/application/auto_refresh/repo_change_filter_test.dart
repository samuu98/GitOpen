import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auto_refresh/repo_change_watcher.dart';

void main() {
  const root = r'C:\repos\demo';

  group('isRelevantRepoEvent', () {
    test('worktree file changes are relevant', () {
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\lib\main.dart'), isTrue);
    });

    test('.git internals are irrelevant by default', () {
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\objects\ab\cdef'),
          isFalse);
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\logs\HEAD'),
          isFalse);
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\FETCH_HEAD'),
          isFalse);
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git'), isFalse);
    });

    test('git state files are relevant', () {
      for (final f in [
        'HEAD', 'ORIG_HEAD', 'MERGE_HEAD', 'CHERRY_PICK_HEAD',
        'REVERT_HEAD', 'packed-refs',
      ]) {
        expect(isRelevantRepoEvent(root, 'C:\\repos\\demo\\.git\\$f'), isTrue,
            reason: f);
      }
    });

    test('index writes are NOT relevant (self-refresh feedback loop)', () {
      // The app's own `git status` runs rewrite .git/index to refresh the
      // stat cache; treating that as an external change made every refresh
      // schedule the next one, looping forever (see 2026-06-12 incident).
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\index'), isFalse);
    });

    test('refs are relevant, their lock files are not', () {
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\refs\heads\main'),
          isTrue);
      expect(
          isRelevantRepoEvent(
              root, r'C:\repos\demo\.git\refs\remotes\origin\main'),
          isTrue);
      expect(
          isRelevantRepoEvent(root, r'C:\repos\demo\.git\refs\heads\main.lock'),
          isFalse);
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\index.lock'),
          isFalse);
    });

    test('posix separators work too', () {
      expect(
          isRelevantRepoEvent(
              '/home/u/demo', '/home/u/demo/.git/refs/heads/main'),
          isTrue);
      expect(
          isRelevantRepoEvent('/home/u/demo', '/home/u/demo/.git/objects/aa/bb'),
          isFalse);
      expect(isRelevantRepoEvent('/home/u/demo', '/home/u/demo/src/app.dart'),
          isTrue);
    });
  });
}
