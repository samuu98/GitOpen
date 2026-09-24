import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_panel_state.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/github/github_api_state.dart';
import 'package:gitopen/ui/github/github_mutation.dart';
import 'package:gitopen/ui/github/github_providers.dart';
import 'package:gitopen/ui/github/pull_request_files_view.dart';
import 'package:gitopen/ui/github/pull_request_forms.dart';
import 'package:gitopen/ui/github/pull_request_review_drawer.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class PullRequestDetailView extends ConsumerStatefulWidget {
  const PullRequestDetailView({
    required this.repo,
    required this.slug,
    required this.token,
    required this.number,
    super.key,
  });

  final RepoLocation repo;
  final RepoSlug slug;
  final String token;
  final int number;

  @override
  ConsumerState<PullRequestDetailView> createState() =>
      _PullRequestDetailViewState();
}

class _PullRequestDetailViewState extends ConsumerState<PullRequestDetailView> {
  String? _error;
  bool _pending = false;
  final List<QueuedReviewComment> _queuedComments = [];

  @override
  Widget build(BuildContext context) {
    final key = (
      slug: widget.slug,
      token: widget.token,
      number: widget.number,
    );
    final detailAsync = ref.watch(githubPullRequestDetailProvider(key));
    return detailAsync.when(
      skipLoadingOnReload: true,
      loading: () => const AppLoadingState.detail(),
      error: (e, _) => GitHubApiErrorView(
        error: e,
        onRetry: () => ref.invalidate(githubPullRequestDetailProvider(key)),
      ),
      data: (detail) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PullRequestHeader(
            detail: detail,
            error: _error,
            pending: _pending,
            onEdit: () => _edit(detail),
            onClose: _close,
            onReopen: () => _update(
              const UpdatePullRequestRequest(state: 'open'),
              successMessage: 'Pull request reopened.',
            ),
            onReady: detail.isDraft ? () => _ready(detail) : null,
            onMerge: () => _merge(detail),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final files = PullRequestFilesView(
                  slug: widget.slug,
                  token: widget.token,
                  number: widget.number,
                  onLineCommentRequested: _queueLineComment,
                );
                final drawer = PullRequestReviewDrawer(
                  repo: widget.repo,
                  slug: widget.slug,
                  token: widget.token,
                  number: widget.number,
                  queuedComments: _queuedComments,
                  onClearQueuedComments: () => setState(_queuedComments.clear),
                );
                if (constraints.maxWidth < 420) {
                  return Column(
                    children: [
                      Expanded(child: files),
                      SizedBox(height: 160, child: drawer),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: files),
                    drawer,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _close() async {
    if (_pending) return;
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Close pull request?',
      body:
          'Pull request #${widget.number} will be closed. It can be reopened.',
      confirmLabel: 'Close',
      dangerous: true,
    );
    if (!confirmed || !mounted) return;
    await _update(
      const UpdatePullRequestRequest(state: 'closed'),
      successMessage: 'Pull request closed.',
    );
  }

  Future<void> _edit(PullRequestDetail detail) async {
    final result = await showEditPullRequestDialog(context, detail);
    if (result == null || !mounted) return;
    await _update(result.request, successMessage: 'Pull request updated.');
  }

  Future<void> _update(
    UpdatePullRequestRequest request, {
    required String successMessage,
  }) async {
    await _runMutation(() async {
      await ref
          .read(gitHubApiProvider)
          .updatePullRequest(
            widget.slug,
            widget.number,
            request,
            token: widget.token,
          );
    }, successMessage: successMessage);
  }

  Future<void> _ready(PullRequestDetail detail) async {
    await _runMutation(() async {
      await ref
          .read(gitHubApiProvider)
          .markPullRequestReadyForReview(
            widget.slug,
            detail.number,
            token: widget.token,
          );
    }, successMessage: 'Pull request marked ready.');
  }

  Future<void> _merge(PullRequestDetail detail) async {
    final result = await showMergePullRequestDialog(context);
    if (result == null || !mounted) return;
    await _runMutation(
      () async {
        await ref
            .read(gitHubApiProvider)
            .mergePullRequest(
              widget.slug,
              detail.number,
              result.request,
              token: widget.token,
            );
      },
      successMessage: 'Pull request merged.',
      merge: true,
    );
  }

  Future<void> _runMutation(
    Future<void> Function() op, {
    required String successMessage,
    bool merge = false,
  }) async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await runGitHubMutation<void>(
        ref,
        repo: widget.repo,
        key: 'pr/${widget.number}',
        slug: widget.slug,
        token: widget.token,
        pullRequest: widget.number,
        scopes: merge ? {RefreshScope.graph, RefreshScope.sidebar} : const {},
        successMessage: successMessage,
        action: op,
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _queueLineComment(String path, int line, String side) async {
    final comment = await showLineCommentDialog(
      context,
      path: path,
      line: line,
      side: side,
    );
    if (comment == null || !mounted) return;
    setState(() => _queuedComments.add(comment));
  }
}

class _PullRequestHeader extends StatelessWidget {
  const _PullRequestHeader({
    required this.detail,
    required this.error,
    required this.pending,
    required this.onEdit,
    required this.onClose,
    required this.onReopen,
    required this.onReady,
    required this.onMerge,
  });

  final PullRequestDetail detail;
  final String? error;
  final bool pending;
  final VoidCallback onEdit;
  final VoidCallback onClose;
  final VoidCallback onReopen;
  final VoidCallback? onReady;
  final VoidCallback onMerge;

  String _mergeTooltip(MergeBlock block) => switch (block) {
    MergeBlock.none => 'Merge this pull request',
    MergeBlock.notOpen => 'This pull request is not open',
    MergeBlock.draft => 'Mark the draft as ready before merging',
    MergeBlock.conflicts => 'Resolve the merge conflicts first',
    MergeBlock.blocked =>
      'Blocked by branch protection (required checks or reviews)',
    MergeBlock.behind => 'This branch is out of date with the base branch',
    MergeBlock.checking => 'GitHub is still checking if this can be merged',
  };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'PR #${detail.number}',
                style: TextStyle(
                  color: palette.accentRemote,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              _StateChip(detail: detail),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  detail.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.fg0,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${detail.baseRef} <- ${detail.headRef}',
            style: TextStyle(color: palette.fg2, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            detail.body.isEmpty ? 'No description' : detail.body,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.fg1, fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton.secondary(
                icon: Icons.edit_outlined,
                label: 'Edit',
                onPressed: pending ? null : onEdit,
              ),
              if (detail.isOpen)
                AppButton.secondary(
                  icon: Icons.block,
                  label: 'Close',
                  onPressed: pending ? null : onClose,
                )
              else
                AppButton.secondary(
                  icon: Icons.refresh,
                  label: 'Reopen',
                  onPressed: pending ? null : onReopen,
                ),
              if (onReady != null)
                AppButton.secondary(
                  icon: Icons.publish_outlined,
                  label: pending ? 'Working…' : 'Ready',
                  onPressed: pending ? null : onReady,
                ),
              Tooltip(
                message: _mergeTooltip(detail.mergeBlock),
                child: AppButton.primary(
                  icon: Icons.merge_type,
                  label: 'Merge',
                  onPressed: detail.canMerge && !pending ? onMerge : null,
                ),
              ),
            ],
          ),
          if (pending) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(palette.accentCurrent),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Updating pull request…',
                  style: TextStyle(color: palette.fg2, fontSize: 12),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: TextStyle(color: palette.accentErr, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.detail});

  final PullRequestDetail detail;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final label = detail.isDraft ? 'DRAFT' : detail.state.toUpperCase();
    final color = detail.isDraft
        ? palette.fg2
        : detail.isOpen
        ? palette.accentCurrent
        : palette.fg3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
