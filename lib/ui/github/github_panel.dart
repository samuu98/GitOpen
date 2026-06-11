import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_api.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/auth_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

typedef _ApiKey = ({RepoSlug slug, String token});

final AutoDisposeFutureProviderFamily<List<PullRequestInfo>, _ApiKey>
    _prsProvider =
    FutureProvider.family.autoDispose<List<PullRequestInfo>, _ApiKey>(
  (ref, key) =>
      ref.watch(gitHubApiProvider).listPullRequests(key.slug, token: key.token),
);

final AutoDisposeFutureProviderFamily<
        List<WorkflowRunInfo>,
        ({RepoSlug slug, String token, String? branch})> _runsProvider =
    FutureProvider.family.autoDispose<
        List<WorkflowRunInfo>,
        ({RepoSlug slug, String token, String? branch})>(
  (ref, key) => ref
      .watch(gitHubApiProvider)
      .listWorkflowRuns(key.slug, token: key.token, branch: key.branch),
);

final AutoDisposeFutureProviderFamily<
        CheckSummary,
        ({RepoSlug slug, String token, String sha})> _checksProvider =
    FutureProvider.family.autoDispose<
        CheckSummary,
        ({RepoSlug slug, String token, String sha})>(
  (ref, key) => ref
      .watch(gitHubApiProvider)
      .prChecks(key.slug, key.sha, token: key.token),
);

/// GitHub view for a github.com repo: open Pull Requests (with per-PR
/// checkout + check status) and recent Actions runs for the current branch.
/// No usable token -> inline device-flow sign-in CTA; API failures render
/// inline and never block local git work.
class GitHubPanel extends ConsumerStatefulWidget {
  const GitHubPanel({required this.repo, super.key});
  final RepoLocation repo;

  @override
  ConsumerState<GitHubPanel> createState() => _GitHubPanelState();
}

class _GitHubPanelState extends ConsumerState<GitHubPanel> {
  String _tab = 'prs';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final slug = ref.watch(githubSlugProvider(widget.repo)).valueOrNull;
    if (slug == null) {
      return Center(
        child: Text(
          'Not a GitHub repository',
          style: TextStyle(
            color: palette.fg3,
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    final profileAsync = ref.watch(repoActiveProfileProvider(widget.repo));
    if (profileAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final token = githubTokenOf(profileAsync.valueOrNull?.spec);
    if (token == null) {
      return _SignInCta(repo: widget.repo);
    }
    return Column(
      children: [
        _TabsBar(active: _tab, onSelect: (v) => setState(() => _tab = v)),
        Expanded(
          child: _tab == 'prs'
              ? _PullRequestsTab(repo: widget.repo, slug: slug, token: token)
              : _ActionsTab(repo: widget.repo, slug: slug, token: token),
        ),
      ],
    );
  }
}

class _TabsBar extends StatelessWidget {
  const _TabsBar({required this.active, required this.onSelect});
  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      color: palette.bg3,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _Tab(
            label: 'Pull Requests',
            value: 'prs',
            active: active,
            onSelect: onSelect,
          ),
          _Tab(
            label: 'Actions',
            value: 'actions',
            active: active,
            onSelect: onSelect,
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.value,
    required this.active,
    required this.onSelect,
  });
  final String label;
  final String value;
  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isActive = active == value;
    return InkWell(
      onTap: () => onSelect(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? palette.accentCurrent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? palette.fg0 : palette.fg1,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInCta extends ConsumerWidget {
  const _SignInCta({required this.repo});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 32, color: palette.fg3),
          const SizedBox(height: 10),
          Text(
            'Sign in to see pull requests and workflow runs.',
            style: TextStyle(color: palette.fg2, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.login, size: 14),
            label: const Text('Sign in with GitHub'),
            onPressed: () async {
              final profile = await AuthDialog.show(context, 'github.com');
              if (profile == null) return;
              await ref
                  .read(appSettingsProvider.notifier)
                  .setAuthBinding(repo.id.value, profile.id);
              ref.invalidate(repoActiveProfileProvider(repo));
            },
          ),
        ],
      ),
    );
  }
}

class _ApiError extends StatelessWidget {
  const _ApiError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final message = error is GitHubApiException
        ? error.toString()
        : 'GitHub request failed: $error';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.fg2, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _PullRequestsTab extends ConsumerWidget {
  const _PullRequestsTab({
    required this.repo,
    required this.slug,
    required this.token,
  });
  final RepoLocation repo;
  final RepoSlug slug;
  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final key = (slug: slug, token: token);
    final async = ref.watch(_prsProvider(key));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          _ApiError(error: e, onRetry: () => ref.invalidate(_prsProvider(key))),
      data: (prs) => prs.isEmpty
          ? Center(
              child: Text(
                'No open pull requests',
                style: TextStyle(
                  color: palette.fg3,
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: prs.length,
              itemBuilder: (_, i) => _PullRequestRow(
                repo: repo,
                slug: slug,
                token: token,
                pr: prs[i],
              ),
            ),
    );
  }
}

class _PullRequestRow extends ConsumerWidget {
  const _PullRequestRow({
    required this.repo,
    required this.slug,
    required this.token,
    required this.pr,
  });
  final RepoLocation repo;
  final RepoSlug slug;
  final String token;
  final PullRequestInfo pr;

  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
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
          Text(
            '#${pr.number}',
            style: TextStyle(
              color: palette.accentRemote,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 10),
          if (pr.isDraft) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: palette.fg3.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'DRAFT',
                style: TextStyle(
                  color: palette.fg2,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pr.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.fg0, fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  pr.author,
                  style: TextStyle(color: palette.fg3, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CheckChip(slug: slug, token: token, sha: pr.headSha),
          const SizedBox(width: 8),
          Text(
            _dateFmt.format(pr.updatedAt.toLocal()),
            style: TextStyle(color: palette.fg3, fontSize: 10.5),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Checkout PR as pr/${pr.number}',
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: () => ref
                  .read(gitActionsControllerProvider)
                  .checkoutPullRequest(context, repo, pr.number),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.call_split, size: 15, color: palette.fg1),
              ),
            ),
          ),
          Tooltip(
            message: 'Open on GitHub',
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: () => launchUrl(
                Uri.parse(pr.htmlUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.open_in_new,
                  size: 14,
                  color: palette.fg1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckChip extends ConsumerWidget {
  const _CheckChip({
    required this.slug,
    required this.token,
    required this.sha,
  });
  final RepoSlug slug;
  final String token;
  final String sha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async =
        ref.watch(_checksProvider((slug: slug, token: token, sha: sha)));
    final summary = async.valueOrNull;
    if (summary == null || summary.state == CheckState.none) {
      return const SizedBox.shrink();
    }
    final (icon, color) = switch (summary.state) {
      CheckState.success => (Icons.check_circle_outline, palette.accentCurrent),
      CheckState.failure => (Icons.cancel_outlined, palette.accentErr),
      CheckState.pending => (Icons.schedule, palette.accentWarn),
      CheckState.none => (Icons.remove, palette.fg3),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          '${summary.succeeded}/${summary.total}',
          style: TextStyle(color: color, fontSize: 11),
        ),
      ],
    );
  }
}

class _ActionsTab extends ConsumerWidget {
  const _ActionsTab({
    required this.repo,
    required this.slug,
    required this.token,
  });
  final RepoLocation repo;
  final RepoSlug slug;
  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final branch =
        ref.watch(repoStatusProvider(repo)).valueOrNull?.currentBranch;
    final key = (slug: slug, token: token, branch: branch);
    final async = ref.watch(_runsProvider(key));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ApiError(
        error: e,
        onRetry: () => ref.invalidate(_runsProvider(key)),
      ),
      data: (runs) => runs.isEmpty
          ? Center(
              child: Text(
                branch == null
                    ? 'No workflow runs'
                    : 'No workflow runs for $branch',
                style: TextStyle(
                  color: palette.fg3,
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
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
          Tooltip(
            message: 'Open on GitHub',
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: () => launchUrl(
                Uri.parse(run.htmlUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.open_in_new,
                  size: 14,
                  color: palette.fg1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
