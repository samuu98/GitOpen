import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/repositories/repo_id.dart';
import '../domain/commits/commit_sha.dart';

final activeWorkspaceIdProvider = StateProvider<RepoId?>((_) => null);
final selectedCommitShaProvider = StateProvider<CommitSha?>((_) => null);

/// Incrementing counter — CommitCompose watches this and triggers a commit
/// whenever the value changes (i.e. on each Ctrl+Enter key event).
final triggerCommitProvider = StateProvider<int>((_) => 0);

/// Incrementing counter — the Shell watches this and fetches the active repo
/// whenever it changes (F5, or the command palette's "Fetch" command).
final triggerFetchProvider = StateProvider<int>((_) => 0);

/// Incrementing counter — GitToolbar listens and pulls the active repo with
/// the default strategy (command palette's "Pull" command).
final triggerPullProvider = StateProvider<int>((_) => 0);

/// Incrementing counter — GitToolbar listens and pushes the current branch
/// (command palette's "Push" command).
final triggerPushProvider = StateProvider<int>((_) => 0);
