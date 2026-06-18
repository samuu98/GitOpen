import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/main_view_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/scroll_request_provider.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// Left-indent scheme for the sidebar tree, centralized so section headers,
/// tree nodes, flat rows and empty hints stay aligned. These literals used to
/// live independently in each section file and drifted out of sync twice
/// (the section header ending up *more* indented than its own children).
///
/// - [kSidebarChevronIndent]: x of a section-header chevron and of a
///   top-level (depth-0) tree chevron — they line up in the same column.
/// - [kSidebarIndentStep]: extra indent per nesting level.
/// - [kSidebarLeafExtra]: a leaf node's text sits this far past its chevron
///   column (where a sibling folder's chevron would be).
/// - [kSidebarRowIndent]: flat rows (tags, stashes, submodules, worktrees)
///   and empty hints, lined up under the section title.
const double kSidebarChevronIndent = 14;
const double kSidebarIndentStep = 14;
const double kSidebarLeafExtra = 18;
const double kSidebarRowIndent = 26;

/// Selects [sha] in the graph and asks the graph panel to scroll it into
/// view. Also switches the main view back to the graph if the user is
/// currently looking at the working-copy changes.
void revealCommit(WidgetRef ref, CommitSha sha) {
  ref.read(mainViewProvider.notifier).state = MainView.graph;
  ref.read(selectedCommitShaProvider.notifier).state = sha;
  ref.read(scrollRequestProvider.notifier).state = sha;
}

/// Everything the sidebar renders for one repository, loaded in one shot so
/// the panel appears atomically.
class SidebarData {
  SidebarData(
    this.branches,
    this.tags,
    this.remotes,
    this.stashes,
    this.submodules,
    this.worktrees,
  );
  final List<Branch> branches;
  final List<Tag> tags;
  final List<Remote> remotes;
  final List<Stash> stashes;
  final List<Submodule> submodules;
  final List<Worktree> worktrees;
}

final sidebarDataProvider =
    FutureProvider.family<SidebarData, RepoLocation>((ref, repo) async {
  final logger = ref.read(loggerProvider);
  final git = ref.watch(gitReadOperationsProvider);
  logger.i('sidebar: loading all sections for ${repo.displayName}');
  // All six loads are independent — run them concurrently; the panel still
  // appears atomically once the slowest completes.
  final (branches, tags, remotes, stashes, submodules, worktrees) = await (
    ref.watch(branchesProvider(repo).future),
    git.getTags(repo),
    git.getRemotes(repo),
    git.getStashes(repo),
    git.getSubmodules(repo),
    git.getWorktrees(repo),
  ).wait;
  logger.i('sidebar: ${branches.length} branches, ${tags.length} tags, '
      '${remotes.length} remotes, ${stashes.length} stashes, '
      '${submodules.length} submodules, ${worktrees.length} worktrees');
  return SidebarData(branches, tags, remotes, stashes, submodules, worktrees);
});
