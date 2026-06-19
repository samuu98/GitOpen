import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/github/github_api_state.dart';
import 'package:gitopen/ui/github/github_providers.dart';
import 'package:gitopen/ui/github/workflow_run_detail_view.dart';
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
            slug: widget.slug,
            token: widget.token,
            run: runs[i],
            onOpen: () => setState(() => _selectedRunId = runs[i].id),
            onChanged: () => ref.invalidate(githubWorkflowRunsProvider(key)),
          ),
        );
      },
    );
  }
}

class _RunRow extends ConsumerWidget {
  const _RunRow({
    required this.slug,
    required this.token,
    required this.run,
    required this.onOpen,
    required this.onChanged,
  });

  final RepoSlug slug;
  final String token;
  final WorkflowRunInfo run;
  final VoidCallback onOpen;
  final VoidCallback onChanged;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() op,
  ) async {
    try {
      await op();
      onChanged();
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
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
    return Material(
      color: palette.bg1,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onOpen,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
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
                  onPressed: () => _act(
                    context,
                    ref,
                    () => api.cancelWorkflowRun(slug, run.id, token: token),
                  ),
                ),
              if (run.conclusion == 'failure')
                AppIconButton(
                  icon: Icons.replay_circle_filled_outlined,
                  tooltip: 'Re-run failed jobs',
                  onPressed: () => _act(
                    context,
                    ref,
                    () => api.rerunFailedJobs(slug, run.id, token: token),
                  ),
                ),
              AppIconButton(
                icon: Icons.refresh,
                tooltip: 'Re-run all jobs',
                onPressed: () => _act(
                  context,
                  ref,
                  () => api.rerunWorkflowRun(slug, run.id, token: token),
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
      ),
    );
  }
}
