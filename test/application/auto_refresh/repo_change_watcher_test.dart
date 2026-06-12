import 'dart:async';
import 'dart:io' show FileSystemException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auto_refresh/repo_change_watcher.dart';
import 'package:watcher/watcher.dart';

void main() {
  const root = '/repo';
  WatchEvent ev(String path) => WatchEvent(ChangeType.MODIFY, path);

  test('coalesces a burst of relevant events into one callback', () {
    fakeAsync((async) {
      final controller = StreamController<WatchEvent>(sync: true);
      var calls = 0;
      final w = RepoChangeWatcher(
        repoRoot: root,
        onChanged: () => calls++,
        watchStream: (_) => controller.stream,
      );
      controller.add(ev('$root/.git/refs/heads/main'));
      controller.add(ev('$root/.git/refs/remotes/origin/main'));
      controller.add(ev('$root/.git/HEAD'));
      async.elapse(const Duration(milliseconds: 599));
      expect(calls, 0, reason: 'still inside debounce window');
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, 1);
      w.dispose();
    });
  });

  test('irrelevant events never fire the callback', () {
    fakeAsync((async) {
      final controller = StreamController<WatchEvent>(sync: true);
      var calls = 0;
      final w = RepoChangeWatcher(
        repoRoot: root,
        onChanged: () => calls++,
        watchStream: (_) => controller.stream,
      );
      controller.add(ev('$root/.git/objects/aa/bb'));
      controller.add(ev('$root/.git/index.lock'));
      async.elapse(const Duration(seconds: 5));
      expect(calls, 0);
      w.dispose();
    });
  });

  test('dispose cancels a pending debounce', () {
    fakeAsync((async) {
      final controller = StreamController<WatchEvent>(sync: true);
      var calls = 0;
      final w = RepoChangeWatcher(
        repoRoot: root,
        onChanged: () => calls++,
        watchStream: (_) => controller.stream,
      );
      controller.add(ev('$root/file.txt'));
      w.dispose();
      async.elapse(const Duration(seconds: 5));
      expect(calls, 0);
    });
  });

  test('stream error stops the watcher without throwing', () {
    fakeAsync((async) {
      final controller = StreamController<WatchEvent>(sync: true);
      var calls = 0;
      final w = RepoChangeWatcher(
        repoRoot: root,
        onChanged: () => calls++,
        watchStream: (_) => controller.stream,
      );
      controller.addError(const FileSystemException('gone'));
      controller.add(ev('$root/file.txt'));
      async.elapse(const Duration(seconds: 5));
      expect(calls, 0);
      expect(w.isActive, isFalse);
      w.dispose();
    });
  });
}
