import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/repositories/repo_id.dart';
import '../domain/commits/commit_sha.dart';

final activeWorkspaceIdProvider = StateProvider<RepoId?>((_) => null);
final selectedCommitShaProvider = StateProvider<CommitSha?>((_) => null);
final localChangesSelectedProvider = StateProvider<bool>((_) => false);
