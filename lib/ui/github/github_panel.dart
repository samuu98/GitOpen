import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_api.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/github/actions_tab.dart';
import 'package:gitopen/ui/github/github_api_state.dart';
import 'package:gitopen/ui/github/github_tabs_bar.dart';
import 'package:gitopen/ui/github/pull_requests_tab.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

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
    final slug = ref.watch(githubSlugProvider(widget.repo)).value;
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
    final token = githubTokenOf(profileAsync.value?.spec);
    if (token == null) return GitHubSignInCta(repo: widget.repo);
    return Column(
      children: [
        GitHubTabsBar(active: _tab, onSelect: (v) => setState(() => _tab = v)),
        Expanded(
          child: _tab == 'prs'
              ? PullRequestsTab(repo: widget.repo, slug: slug, token: token)
              : GitHubActionsTab(repo: widget.repo, slug: slug, token: token),
        ),
      ],
    );
  }
}
