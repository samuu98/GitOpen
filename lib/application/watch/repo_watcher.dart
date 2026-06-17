import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// Emits a [RepoChange] whenever the repository's git bookkeeping changes on
/// disk (commit, checkout, fetch, merge… from ANY process). Implemented over
/// the file system in infrastructure; injected so auto-refresh is testable.
// Intentional DI seam: implemented by IoRepoWatcher and faked in tests, so it
// must stay an interface rather than collapse into a top-level function.
// ignore: one_member_abstracts
abstract interface class RepoWatcher {
  /// A stream of typed change signals for [repo]. Never errors: watcher
  /// failures (deleted repo, permissions) end the stream instead.
  Stream<RepoChange> changes(RepoLocation repo);
}
