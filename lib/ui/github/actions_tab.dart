import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_animated_row.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/common/app_panel_state.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/github/github_api_state.dart';
import 'package:gitopen/ui/github/github_mutation.dart';
import 'package:gitopen/ui/github/github_providers.dart';
import 'package:gitopen/ui/github/workflow_run_detail_view.dart';
import 'package:gitopen/ui/operations/action_feedback.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:url_launcher/url_launcher.dart';

typedef _RunsKey = ({RepoSlug slug, String token, String? branch});

class GitHubActionsTab extends ConsumerStatefulWidget {
  const GitHubActionsTab({
    required this.repo,
    required this.slug,
    required this.token,
    super.key,
  });

  final RepoLocation repo;
  final RepoSlug slug;
  final String token;

  @override
  ConsumerState<GitHubActionsTab> createState() => _GitHubActionsTabState();
}

class _GitHubActionsTabState extends ConsumerState<GitHubActionsTab> {
  static const _pollInterval = Duration(seconds: 5);
  Timer? _poll;
  int? _selectedRunId;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  // One-shot reschedule while a run is non-terminal; cancelled once everything
  // is done so it never leaves a pending timer for `pumpAndSettle`.
  void _schedulePoll({required bool ongoing, required _RunsKey key}) {
    _poll?.cancel();
    if (!ongoing) return;
    _poll = Timer(_pollInterval, () {
      if (mounted) ref.invalidate(githubWorkflowRunsProvider(key));
    });
  }

  @override
  Widget build(BuildContext context) {
    final branch = ref
        .watch(repoStatusProvider(widget.repo))
        .value
        ?.currentBranch;
    final key = (slug: widget.slug, token: widget.token, branch: branch);
    final async = ref.watch(githubWorkflowRunsProvider(key));
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const AppLoadingState.list(),
      error: (e, _) => GitHubApiErrorView(
        error: e,
        onRetry: () => ref.invalidate(githubWorkflowRunsProvider(key)),
      ),
      data: (runs) {
        _schedulePoll(ongoing: runs.any((r) => !r.isCompleted), key: key);

        WorkflowRunInfo? selected;
        if (_selectedRunId != null) {
          for (final r in runs) {
            if (r.id == _selectedRunId) {
              selected = r;
              break;
            }
          }
        }
        if (selected != null) {
          return WorkflowRunDetailView(
            repo: widget.repo,
            branch: branch,
            slug: widget.slug,
            token: widget.token,
            run: selected,
            onBack: () => setState(() => _selectedRunId = null),
          );
        }

        if (runs.isEmpty) {
          return AppEmptyState(
            icon: Icons.play_circle_outline,
            title: branch == null
                ? 'No workflow runs'
                : 'No workflow runs for $branch',
            message: 'Recent GitHub Actions activity will appear here.',
            actionIcon: Icons.refresh,
            actionLabel: 'Refresh',
            onAction: () => ref.invalidate(githubWorkflowRunsProvider(key)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: runs.length,
          itemBuilder: (_, i) => _RunRow(
            repo: widget.repo,
            branch: branch,
            slug: widget.slug,
            token: widget.token,
            run: runs[i],
            onOpen: () => setState(() => _selectedRunId = runs[i].id),
          ),
        );
      },
    );
  }
}

class _RunRow extends ConsumerWidget {
  const _RunRow({
    required this.repo,
    required this.branch,
    required this.slug,
    required this.token,
    required this.run,
    required this.onOpen,
  });

  final RepoLocation repo;
  final String? branch;
  final RepoSlug slug;
  final String token;
  final WorkflowRunInfo run;
  final VoidCallback onOpen;
  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() op,
    String successMessage, {
    bool cancel = false,
  }) async {
    if (githubMutationPending(ref, repo, 'run/${run.id}')) return;
    if (cancel) {
      final confirmed = await ConfirmDialog.show(
        context,
        title: 'Cancel workflow run?',
        body: 'The workflow run "${run.name}" will be cancelled.',
        confirmLabel: 'Cancel run',
        dangerous: true,
      );
      if (!confirmed || !context.mounted) return;
    }
    try {
      await runGitHubMutation<void>(
        ref,
        repo: repo,
        key: 'run/${run.id}',
        slug: slug,
        token: token,
        runId: run.id,
        branch: branch,
        successMessage: successMessage,
        action: op,
      );
    } on Object catch (e) {
      ref.read(actionFeedbackProvider).showActionFailure('$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final (icon, color) = workflowStatusVisual(
      run.status,
      run.conclusion,
      palette,
    );
    final api = ref.read(gitHubApiProvider);
    final pending = githubMutationPending(ref, repo, 'run/${run.id}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppAnimatedRow(
        selected: false,
        height: AppSpacing.of(context).regularControlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onTap: onOpen,
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            if (pending) ...[
              const SizedBox(width: 6),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                run.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.fg0, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              run.headBranch,
              style: TextStyle(color: palette.accentRemote, fontSize: 11),
            ),
            if (run.isCompleted) ...[
              const SizedBox(width: 10),
              Text(
                '${run.duration.inMinutes}m ${run.duration.inSeconds % 60}s',
                style: TextStyle(color: palette.fg3, fontSize: 11),
              ),
            ],
            const SizedBox(width: 6),
            if (!run.isCompleted)
              AppIconButton(
                icon: Icons.cancel_outlined,
                tooltip: 'Cancel run',
                onPressed: pending
                    ? null
                    : () => _act(
                        context,
                        ref,
                        () => api.cancelWorkflowRun(slug, run.id, token: token),
                        'Workflow run cancelled.',
                        cancel: true,
                      ),
              ),
            if (run.conclusion == 'failure')
              AppIconButton(
                icon: Icons.replay_circle_filled_outlined,
                tooltip: 'Re-run failed jobs',
                onPressed: pending
                    ? null
                    : () => _act(
                        context,
                        ref,
                        () => api.rerunFailedJobs(slug, run.id, token: token),
                        'Failed jobs started again.',
                      ),
              ),
            AppIconButton(
              icon: Icons.refresh,
              tooltip: 'Re-run all jobs',
              onPressed: pending
                  ? null
                  : () => _act(
                      context,
                      ref,
                      () => api.rerunWorkflowRun(slug, run.id, token: token),
                      'Workflow run started again.',
                    ),
            ),
            AppIconButton(
              icon: Icons.open_in_new,
              tooltip: 'Open on GitHub',
              onPressed: () => launchUrl(
                Uri.parse(run.htmlUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
