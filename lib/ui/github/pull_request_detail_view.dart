import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/github/github_api_state.dart';
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
            onEdit: () => _edit(detail),
            onClose: () => _update(
              const UpdatePullRequestRequest(state: 'closed'),
              successMessage: 'Pull request closed.',
            ),
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

  void _invalidate() {
    final detailKey = (
      slug: widget.slug,
      token: widget.token,
      number: widget.number,
    );
    ref
      ..invalidate(githubPullRequestDetailProvider(detailKey))
      ..invalidate(
        githubPullRequestsProvider((slug: widget.slug, token: widget.token)),
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
      _invalidate();
      return successMessage;
    });
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
      _invalidate();
      return 'Pull request marked ready.';
    });
  }

  Future<void> _merge(PullRequestDetail detail) async {
    final result = await showMergePullRequestDialog(context);
    if (result == null || !mounted) return;
    await _runMutation(() async {
      await ref
          .read(gitHubApiProvider)
          .mergePullRequest(
            widget.slug,
            detail.number,
            result.request,
            token: widget.token,
          );
      _invalidate();
      return 'Pull request merged.';
    });
  }

  Future<void> _runMutation(Future<String> Function() op) async {
    setState(() => _error = null);
    try {
      final message = await op();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
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
    required this.onEdit,
    required this.onClose,
    required this.onReopen,
    required this.onReady,
    required this.onMerge,
  });

  final PullRequestDetail detail;
  final String? error;
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
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text('Edit'),
                onPressed: onEdit,
              ),
              if (detail.isOpen)
                OutlinedButton.icon(
                  icon: const Icon(Icons.block, size: 14),
                  label: const Text('Close'),
                  onPressed: onClose,
                )
              else
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Reopen'),
                  onPressed: onReopen,
                ),
              if (onReady != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.publish_outlined, size: 14),
                  label: const Text('Ready'),
                  onPressed: onReady,
                ),
              Tooltip(
                message: _mergeTooltip(detail.mergeBlock),
                child: FilledButton.icon(
                  icon: const Icon(Icons.merge_type, size: 14),
                  label: const Text('Merge'),
                  onPressed: detail.canMerge ? onMerge : null,
                ),
              ),
            ],
          ),
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
