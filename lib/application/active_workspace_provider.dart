import 'package:flutter_riverpod/legacy.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';

final activeWorkspaceIdProvider = StateProvider<RepoId?>((_) => null);
final selectedCommitShaProvider = StateProvider<CommitSha?>((_) => null);

/// Whether the graph's "Local Changes" row is the current bottom-panel
/// selection. When true (and no commit is selected) the bottom panel shows the
/// working-copy staging UI inline, so the user can stage and commit without
/// leaving the graph. A selected commit takes precedence over this flag.
final localChangesSelectedProvider = StateProvider<bool>((_) => false);

/// Incrementing counter — CommitCompose watches this and triggers a commit
/// whenever the value changes (i.e. on each Ctrl+Enter key event).
final triggerCommitProvider = StateProvider<int>((_) => 0);
