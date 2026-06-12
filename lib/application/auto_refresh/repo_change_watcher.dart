import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../../infrastructure/logging/app_logger.dart';

/// Git state files inside `.git/` whose change means "repo state moved".
const _gitStateFiles = {
  'HEAD', 'ORIG_HEAD', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD',
  'index', 'packed-refs',
};

/// Whether a filesystem event at [eventPath] implies the repo at [repoRoot]
/// changed in a way the UI should reflect.
///
/// Working-tree paths always count (they drive the working-copy panel).
/// Inside `.git/` only ref updates and the well-known state files count;
/// object/pack writes, reflogs and `*.lock` churn are noise.
bool isRelevantRepoEvent(String repoRoot, String eventPath) {
  final rel = p.relative(eventPath, from: repoRoot).replaceAll('\\', '/');
  if (rel != '.git' && !rel.startsWith('.git/')) return true;
  if (rel == '.git') return false;
  final inner = rel.substring('.git/'.length);
  if (inner.endsWith('.lock')) return false;
  return _gitStateFiles.contains(inner) || inner.startsWith('refs/');
}

typedef WatchStreamFactory = Stream<WatchEvent> Function(String path);

Stream<WatchEvent> _defaultWatchStream(String path) =>
    DirectoryWatcher(path).events;

/// Watches one repository root and invokes [onChanged] (debounced) when the
/// repo changes on disk in a way the UI should reflect — i.e. when
/// [isRelevantRepoEvent] accepts the event.
///
/// On a stream error (deleted directory, unreachable network drive) the
/// watcher logs and stops; the owner's next reconcile recreates it if the
/// repo is still open.
final class RepoChangeWatcher {
  RepoChangeWatcher({
    required this.repoRoot,
    required this.onChanged,
    WatchStreamFactory? watchStream,
    this.debounce = const Duration(milliseconds: 600),
  }) {
    _sub = (watchStream ?? _defaultWatchStream)(repoRoot).listen(
      _onEvent,
      onError: (Object e) {
        appLog.w('Repo watcher stopped for $repoRoot: $e');
        dispose();
      },
    );
  }

  final String repoRoot;
  final void Function() onChanged;
  final Duration debounce;

  StreamSubscription<WatchEvent>? _sub;
  Timer? _debounceTimer;
  bool _disposed = false;

  /// False once disposed or stopped by a stream error.
  bool get isActive => !_disposed;

  void _onEvent(WatchEvent event) {
    if (_disposed || !isRelevantRepoEvent(repoRoot, event.path)) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      if (!_disposed) onChanged();
    });
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _sub?.cancel();
    _sub = null;
  }
}
