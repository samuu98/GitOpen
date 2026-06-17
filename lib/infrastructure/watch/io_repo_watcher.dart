import 'dart:async';
import 'dart:io';

import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/application/watch/repo_watcher.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/logging/app_logger.dart';
import 'package:path/path.dart' as p;

/// [RepoWatcher] over `dart:io` [Directory.watch].
///
/// Watches `<gitdir>` and `<gitdir>/logs` NON-recursively (recursive watching
/// is unsupported on Linux). Direct children of those two dirs cover every
/// external operation worth refreshing for: HEAD (checkout), index (stage/
/// commit), FETCH_HEAD/ORIG_HEAD/MERGE_HEAD (fetch/pull/merge), packed-refs,
/// and logs/HEAD — the reflog touched by every HEAD-moving op. Loose-ref-only
/// changes (e.g. `git branch x` with no checkout) are picked up by the
/// focus-refresh instead. The changed path is classified into a [RepoChange]
/// (see [classifyGitChange]); unclassified paths (index, *.lock, config) are
/// dropped.
class IoRepoWatcher implements RepoWatcher {
  @override
  Stream<RepoChange> changes(RepoLocation repo) {
    final controller = StreamController<RepoChange>();
    final subs = <StreamSubscription<FileSystemEvent>>[];

    controller
      ..onCancel = () async {
        for (final s in subs) {
          await s.cancel();
        }
      }
      ..onListen = () {
        final gitDir = _resolveGitDir(repo.path);
        if (gitDir == null) {
          unawaited(controller.close());
          return;
        }
        final targets = [
          Directory(gitDir),
          Directory(p.join(gitDir, 'logs')),
        ].where((d) => d.existsSync()).toList();
        if (targets.isEmpty) {
          unawaited(controller.close());
          return;
        }
        var open = targets.length;
        for (final t in targets) {
          subs.add(
            t.watch().listen(
              (event) {
                // Classify the changed path; index/lock churn (our own
                // `git status` rewrites the index) and irrelevant files
                // classify to null and are dropped.
                final kind = classifyGitChange(event.path);
                if (kind == null) return;
                if (!controller.isClosed) controller.add(kind);
              },
              onError: (Object e) {
                appLog.w('repo watcher error on ${t.path}: $e');
              },
              onDone: () {
                open--;
                if (open == 0 && !controller.isClosed) {
                  unawaited(controller.close());
                }
              },
            ),
          );
        }
      };
    return controller.stream;
  }

  /// `<repo>/.git` is a directory in a normal checkout, or a `gitdir: <path>`
  /// pointer file in linked worktrees/submodules.
  String? _resolveGitDir(String repoPath) {
    final dotGit = p.join(repoPath, '.git');
    if (Directory(dotGit).existsSync()) return dotGit;
    final f = File(dotGit);
    if (!f.existsSync()) return null;
    try {
      final line = f.readAsLinesSync().firstWhere(
        (l) => l.startsWith('gitdir:'),
        orElse: () => '',
      );
      if (line.isEmpty) return null;
      final target = line.substring('gitdir:'.length).trim();
      return p.isAbsolute(target)
          ? target
          : p.normalize(p.join(repoPath, target));
    } on Object {
      return null;
    }
  }
}
