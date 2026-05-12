import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/repositories/repo_id.dart';
import '../domain/commits/commit_sha.dart';

final activeWorkspaceIdProvider = StateProvider<RepoId?>((_) => null);
final selectedCommitShaProvider = StateProvider<CommitSha?>((_) => null);
final localChangesSelectedProvider = StateProvider<bool>((_) => false);

/// Incrementing counter — CommitCompose watches this and triggers a commit
/// whenever the value changes (i.e. on each Ctrl+Enter key event).
final triggerCommitProvider = StateProvider<int>((_) => 0);
