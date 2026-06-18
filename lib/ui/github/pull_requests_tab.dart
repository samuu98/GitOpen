import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/github/github_api_state.dart';
import 'package:gitopen/ui/github/github_providers.dart';
import 'package:gitopen/ui/github/pull_request_detail_view.dart';
import 'package:gitopen/ui/github/pull_request_forms.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:url_launcher/url_launcher.dart';

class PullRequestsTab extends ConsumerStatefulWidget {
  const PullRequestsTab({
    required this.repo,
    required this.slug,
    required this.token,
    super.key,
  });

  final RepoLocation repo;
  final RepoSlug slug;
  final String token;

  @override
  ConsumerState<PullRequestsTab> createState() => _PullRequestsTabState();
}

class _PullRequestsTabState extends ConsumerState<PullRequestsTab> {
  int? _selectedNumber;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final key = (slug: widget.slug, token: widget.token);
    final async = ref.watch(githubPullRequestsProvider(key));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => GitHubApiErrorView(
        error: e,
        onRetry: () => ref.invalidate(githubPullRequestsProvider(key)),
      ),
      data: (prs) {
        if (prs.isEmpty) {
          return AppEmptyState(
            icon: Icons.merge_type_outlined,
            title: 'No open pull requests',
            message: 'This repository has no open pull requests right now.',
            actionIcon: Icons.refresh,
            actionLabel: 'Refresh',
            onAction: () => ref.invalidate(githubPullRequestsProvider(key)),
          );
        }
        final selected = _selectedNumber;
        return Column(
          children: [
            _PullRequestsToolbar(onCreate: _createPullRequest),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final list = _PullRequestList(
                    repo: widget.repo,
                    slug: widget.slug,
                    token: widget.token,
                    prs: prs,
                    selectedNumber: selected,
                    onSelect: (number) =>
                        setState(() => _selectedNumber = number),
                  );
                  final detail = selected == null
                      ? const _NoPullRequestSelected()
                      : PullRequestDetailView(
                          repo: widget.repo,
                          slug: widget.slug,
                          token: widget.token,
                          number: selected,
                        );
                  if (constraints.maxWidth < 720) {
                    return Column(
                      children: [
                        SizedBox(height: 210, child: list),
                        Container(height: 1, color: palette.border),
                        Expanded(child: detail),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(width: 360, child: list),
                      Container(width: 1, color: palette.border),
                      Expanded(child: detail),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createPullRequest() async {
    final result = await showCreatePullRequestDialog(context);
    if (result == null || !mounted) return;
    try {
      final created = await ref
          .read(gitHubApiProvider)
          .createPullRequest(widget.slug, result.request, token: widget.token);
      ref.invalidate(
        githubPullRequestsProvider((slug: widget.slug, token: widget.token)),
      );
      setState(() => _selectedNumber = created.number);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _PullRequestsToolbar extends StatelessWidget {
  const _PullRequestsToolbar({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: palette.bg2,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Create PR'),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _PullRequestList extends StatelessWidget {
  const _PullRequestList({
    required this.repo,
    required this.slug,
    required this.token,
    required this.prs,
    required this.selectedNumber,
    required this.onSelect,
  });

  final RepoLocation repo;
  final RepoSlug slug;
  final String token;
  final List<PullRequestInfo> prs;
  final int? selectedNumber;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: prs.length,
      itemBuilder: (_, i) => _PullRequestRow(
        repo: repo,
        slug: slug,
        token: token,
        pr: prs[i],
        selected: prs[i].number == selectedNumber,
        onSelect: () => onSelect(prs[i].number),
      ),
    );
  }
}

class _NoPullRequestSelected extends StatelessWidget {
  const _NoPullRequestSelected();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Text(
        'Select a pull request',
        style: TextStyle(
          color: palette.fg3,
          fontSize: 12.5,
          fontStyle: FontStyle.italic,
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
    required this.selected,
    required this.onSelect,
  });

  final RepoLocation repo;
  final RepoSlug slug;
  final String token;
  final PullRequestInfo pr;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Material(
      color: selected ? palette.bgAccent : palette.bg1,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onSelect,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? palette.borderStrong : palette.border,
            ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
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
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.fg3, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CheckChip(slug: slug, token: token, sha: pr.headSha),
              const SizedBox(width: 4),
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
        ),
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
    final async = ref.watch(
      githubChecksProvider((slug: slug, token: token, sha: sha)),
    );
    final summary = async.value;
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
