import 'package:gitopen/domain/repositories/repo_location.dart';

/// Emits an event whenever the repository's git bookkeeping changes on disk
/// (commit, checkout, fetch, merge… from ANY process). Implemented over the
/// file system in infrastructure; injected so auto-refresh is testable.
abstract interface class RepoWatcher {
  /// A stream of change signals for [repo]. Never errors: watcher failures
  /// (deleted repo, permissions) end the stream instead.
  Stream<void> changes(RepoLocation repo);
}
