import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/github/github_api_state.dart';
import 'package:gitopen/ui/github/github_providers.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:url_launcher/url_launcher.dart';

class GitHubActionsTab extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref
        .watch(repoStatusProvider(repo))
        .valueOrNull
        ?.currentBranch;
    final key = (slug: slug, token: token, branch: branch);
    final async = ref.watch(githubWorkflowRunsProvider(key));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => GitHubApiErrorView(
        error: e,
        onRetry: () => ref.invalidate(githubWorkflowRunsProvider(key)),
      ),
      data: (runs) => runs.isEmpty
          ? AppEmptyState(
              icon: Icons.play_circle_outline,
              title: branch == null
                  ? 'No workflow runs'
                  : 'No workflow runs for $branch',
              message: 'Recent GitHub Actions activity will appear here.',
              actionIcon: Icons.refresh,
              actionLabel: 'Refresh',
              onAction: () => ref.invalidate(githubWorkflowRunsProvider(key)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: runs.length,
              itemBuilder: (_, i) => _RunRow(run: runs[i]),
            ),
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run});

  final WorkflowRunInfo run;

  String get _durationLabel {
    final d = run.duration;
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (icon, color) = !run.isCompleted
        ? (Icons.timelapse, palette.accentWarn)
        : switch (run.conclusion) {
            'success' => (Icons.check_circle_outline, palette.accentCurrent),
            'failure' => (Icons.cancel_outlined, palette.accentErr),
            _ => (Icons.remove_circle_outline, palette.fg3),
          };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.bg1,
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
          const SizedBox(width: 10),
          if (run.isCompleted)
            Text(
              _durationLabel,
              style: TextStyle(color: palette.fg3, fontSize: 11),
            ),
          const SizedBox(width: 8),
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
    );
  }
}
