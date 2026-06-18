import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/commit_graph/commit_node.dart';
import 'package:gitopen/application/commit_search_provider.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/scroll_request_provider.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/checkout/safe_checkout.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_search_field.dart';
import 'package:gitopen/ui/commit_graph/commit_row.dart';
import 'package:gitopen/ui/commit_graph/local_changes_row.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/common/skeleton.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/branch_create_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/dialogs/interactive_rebase_dialog.dart';
import 'package:gitopen/ui/dialogs/merge_dialog.dart';
import 'package:gitopen/ui/dialogs/tag_create_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class CommitGraphPanel extends ConsumerStatefulWidget {
  const CommitGraphPanel({required this.repo, super.key});
  final RepoLocation repo;

  @override
  ConsumerState<CommitGraphPanel> createState() => _CommitGraphPanelState();
}

class _CommitGraphPanelState extends ConsumerState<CommitGraphPanel> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadMore);
  }

  /// Grows the loaded window by a page when the user scrolls near the bottom,
  /// unless a load is already in flight or there is nothing more to fetch.
  void _maybeLoadMore() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    if (pos.pixels < pos.maxScrollExtent - 800) return;
    final async = ref.read(commitGraphDataProvider(widget.repo));
    final data = async.value;
    if (data == null || !data.hasMore || async.isLoading) return;
    ref
        .read(graphLimitProvider(widget.repo).notifier)
        .update((n) => n + graphPageSize);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToSha(CommitSha sha, List<CommitNode> nodes) {
    final index = nodes.indexWhere((n) => n.commit.sha == sha);
    if (index < 0 || !_controller.hasClients) return;
    final target = index * 26.0;
    final position = _controller.position;
    final viewport = position.viewportDimension;
    final maxScroll = position.maxScrollExtent;
    // Center the row in the viewport if possible.
    final centered = (target - viewport / 2 + 13).clamp(0.0, maxScroll);
    unawaited(
      _controller.animateTo(
        centered,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final async = ref.watch(commitGraphDataProvider(repo));
    final palette = AppPalette.of(context);

    // Listen for scroll requests from the sidebar / other panels.
    ref.listen<CommitSha?>(scrollRequestProvider, (prev, next) {
      if (next == null) return;
      final data = ref.read(commitGraphDataProvider(repo)).value;
      if (data == null) return;
      // Schedule after the current frame so the ListView has measured.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSha(next, data.nodes);
        ref.read(scrollRequestProvider.notifier).state = null;
      });
    });

    final searchActive = !ref.watch(commitSearchProvider).isEmpty;

    return ColoredBox(
      color: palette.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CommitGraphSearchField(),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              data: (data) {
                if (data.nodes.isEmpty) {
                  return Center(
                    child: Text(
                      searchActive
                          ? 'No commits match the search.'
                          : 'No commits in this repository.',
                      style: TextStyle(color: palette.fg2),
                    ),
                  );
                }
                final selected = ref.watch(selectedCommitShaProvider);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The local-changes pseudo-row only makes sense for the
                    // full graph; hide it while a search is active so results
                    // are exactly the matching commits.
                    if (!searchActive) LocalChangesRow(repo: repo),
                    Expanded(
                      child: ListView.builder(
                        controller: _controller,
                        itemExtent: 26,
                        itemCount: data.nodes.length + (data.hasMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= data.nodes.length) {
                            return const Center(
                              child: SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              ),
                            );
                          }
                          final node = data.nodes[i];
                          final refs =
                              data.refsBySha[node.commit.sha.value] ?? const [];
                          return CommitRow(
                            node: node,
                            maxLane: data.maxLane,
                            refs: refs,
                            isSelected: selected == node.commit.sha,
                            onTap: () {
                              ref
                                      .read(selectedCommitShaProvider.notifier)
                                      .state =
                                  node.commit.sha;
                            },
                            onSecondaryTap: (globalPos) =>
                                _showCommitContextMenu(
                                  context,
                                  ref,
                                  node.commit,
                                  globalPos,
                                ),
                            onRefTap: (r) {
                              ref
                                      .read(selectedCommitShaProvider.notifier)
                                      .state =
                                  node.commit.sha;
                            },
                            onRefDoubleTap: (r) async {
                              final ok = await checkoutRef(
                                context: context,
                                ref: ref,
                                repo: widget.repo,
                                name: r.name,
                                isRemote: r.isRemote,
                              );
                              if (ok) {
                                ref.invalidate(commitGraphDataProvider(repo));
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              loading: () =>
                  const SkeletonList(rows: 18, rowHeight: 11, gap: 15),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load graph: $e',
                    style: TextStyle(color: palette.accentErr),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCommitContextMenu(
    BuildContext context,
    WidgetRef ref,
    CommitInfo commit,
    Offset globalPos,
  ) async {
    final repo = widget.repo;
    final sha = commit.sha;
    final canUndoLastCommit = await _canUndoLastCommit(ref, repo, commit);
    if (!context.mounted) return;
    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: globalPos,
      entries: [
        const AppMenuItem(
          value: 'merge',
          label: 'Merge into current',
          icon: Icons.call_merge,
        ),
        const AppMenuItem(
          value: 'rebase',
          label: 'Rebase current onto this',
          icon: Icons.compare_arrows,
        ),
        const AppMenuItem(
          value: 'interactive_rebase',
          label: 'Interactive rebase from here…',
          icon: Icons.format_list_numbered,
        ),
        const AppMenuItem(
          value: 'reword',
          label: 'Reword message…',
          icon: Icons.edit_note,
        ),
        const AppMenuItem(
          value: 'edit_commit',
          label: 'Edit (amend) here…',
          icon: Icons.build_outlined,
        ),
        const AppMenuDivider(),
        const AppMenuItem(
          value: 'cherry_pick',
          label: 'Cherry-pick into current',
          icon: Icons.add_card_outlined,
        ),
        const AppMenuItem(
          value: 'revert',
          label: 'Revert this commit',
          icon: Icons.undo,
        ),
        const AppMenuDivider(),
        const AppMenuItem(
          value: 'branch_here',
          label: 'Create branch here…',
          icon: Icons.alt_route,
        ),
        const AppMenuItem(
          value: 'tag_here',
          label: 'Tag here…',
          icon: Icons.local_offer_outlined,
        ),
        const AppMenuDivider(),
        const AppMenuItem(
          value: 'copy_sha',
          label: 'Copy SHA',
          icon: Icons.copy,
        ),
        const AppMenuItem(
          value: 'copy_short_sha',
          label: 'Copy short SHA',
          icon: Icons.copy_outlined,
        ),
        const AppMenuDivider(),
        if (canUndoLastCommit) ...const [
          AppMenuItem(
            value: 'undo_last_commit',
            label: 'Undo last commit (soft reset)…',
            icon: Icons.undo_outlined,
          ),
          AppMenuDivider(),
        ],
        const AppMenuItem(
          value: 'reset_soft',
          label: 'Reset (soft)',
          icon: Icons.restore,
        ),
        const AppMenuItem(
          value: 'reset_mixed',
          label: 'Reset (mixed)',
          icon: Icons.restore,
        ),
        const AppMenuItem(
          value: 'reset_hard',
          label: 'Reset (hard)…',
          icon: Icons.restore,
          danger: true,
        ),
      ],
    );

    if (selected == null || !context.mounted) return;

    switch (selected) {
      case 'merge':
        final current = await currentBranchName(ref, repo);
        if (!context.mounted) return;
        final strategy = await MergeDialog.show(
          context,
          repo: repo,
          sourceRef: sha.short(),
          targetRef: current ?? 'HEAD',
        );
        if (strategy == null || !context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .merge(context, repo, sha.value, strategy);

      case 'rebase':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Rebase current branch',
          body:
              'Rebase the current branch onto ${sha.short()}? '
              'This rewrites commits on the current branch.',
          confirmLabel: 'Rebase',
        );
        if (!confirmed || !context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .rebase(context, repo, sha.value);

      case 'interactive_rebase':
        if (!context.mounted) return;
        final plan = await InteractiveRebaseDialog.show(
          context,
          repo: repo,
          onto: sha,
        );
        if (plan == null || !context.mounted) return;
        // On conflict the controller surfaces the snackbar and the
        // ConflictResolutionPanel / repoStateProvider flow takes over.
        await ref
            .read(gitActionsControllerProvider)
            .interactiveRebase(context, repo, sha, plan);

      case 'reword':
        final current = await ref
            .read(gitReadOperationsProvider)
            .getCommitFullMessage(repo, sha);
        if (!context.mounted) return;
        final message = await _promptMultiline(
          context,
          'Reword commit ${sha.short()}',
          label: 'Commit message',
          initial: current ?? '',
        );
        if (message == null || message.trim().isEmpty) return;
        if (!context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .rewordCommit(context, repo, sha, message.trim());

      case 'edit_commit':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Edit commit',
          body:
              'Pause a rebase at ${sha.short()} so you can amend it? '
              'Commits after it will be replayed when you continue. '
              'This rewrites history.',
          confirmLabel: 'Pause here',
        );
        if (!confirmed || !context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .editAtCommit(context, repo, sha);

      case 'cherry_pick':
        await ref
            .read(gitActionsControllerProvider)
            .cherryPick(context, repo, sha);

      case 'revert':
        await ref.read(gitActionsControllerProvider).revert(context, repo, sha);

      case 'branch_here':
        await BranchCreateDialog.show(context, repo, at: sha);

      case 'tag_here':
        if (!context.mounted) return;
        final req = await TagCreateDialog.show(context);
        if (req == null) return;
        if (!context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .createTag(context, repo, req.name, at: sha, message: req.message);

      case 'copy_sha':
        await Clipboard.setData(ClipboardData(text: sha.value));

      case 'copy_short_sha':
        await Clipboard.setData(ClipboardData(text: sha.short()));

      case 'undo_last_commit':
        await _undoLastCommit(context, ref, commit);

      case 'reset_soft':
        await _doReset(context, ref, sha, ResetMode.soft);

      case 'reset_mixed':
        await _doReset(context, ref, sha, ResetMode.mixed);

      case 'reset_hard':
        await _doReset(context, ref, sha, ResetMode.hard);
    }
  }

  Future<bool> _canUndoLastCommit(
    WidgetRef ref,
    RepoLocation repo,
    CommitInfo commit,
  ) async {
    if (commit.parentShas.isEmpty) return false;
    final state = await ref.read(repoStateProvider(repo).future);
    if (state != InProgressOp.none) return false;
    final locals = await ref.read(localBranchesProvider(repo).future);
    return locals.any(
      (b) => b.isCurrent && b.tipSha == commit.sha,
    );
  }

  Future<void> _undoLastCommit(
    BuildContext context,
    WidgetRef ref,
    CommitInfo commit,
  ) async {
    if (commit.parentShas.isEmpty) return;
    final parent = commit.parentShas.first;
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Undo last commit',
      body:
          'Soft reset HEAD from ${commit.sha.short()} to ${parent.short()}? '
          'The commit will be removed from the current branch, with its '
          'changes kept staged.',
      confirmLabel: 'Undo commit',
    );
    if (!confirmed || !context.mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .reset(context, widget.repo, parent, ResetMode.soft);
  }

  Future<void> _doReset(
    BuildContext context,
    WidgetRef ref,
    CommitSha sha,
    ResetMode mode,
  ) async {
    if (mode == ResetMode.hard) {
      if (!context.mounted) return;
      final confirmed = await ConfirmDialog.show(
        context,
        title: 'Hard reset',
        body:
            'This will discard all uncommitted changes and rewrite '
            'history. Are you sure?',
        confirmLabel: 'Reset',
        dangerous: true,
      );
      if (!confirmed) return;
    }
    if (!context.mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .reset(context, widget.repo, sha, mode);
  }

  /// Single-field multiline prompt — used for commit messages.
  Future<String?> _promptMultiline(
    BuildContext context,
    String title, {
    required String label,
    String? initial,
  }) async {
    final ctl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AppDialog(
          title: title,
          width: 520,
          content: TextField(
            controller: ctl,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            style: TextStyle(
              color: palette.fg0,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            decoration: appInputDecoration(ctx, label: label),
          ),
          actions: [
            AppButton.secondary(
              label: 'Cancel',
              onPressed: () => Navigator.pop(ctx),
            ),
            AppButton.primary(
              label: 'OK',
              onPressed: () => Navigator.pop(ctx, ctl.text),
            ),
          ],
        );
      },
    );
    ctl.dispose();
    return result;
  }
}
