import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_api.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/dialogs/auth_dialog.dart';

class GitHubSignInCta extends ConsumerWidget {
  const GitHubSignInCta({required this.repo, super.key});

  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppEmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Sign in to GitHub',
      message: 'Sign in to see pull requests and workflow runs.',
      actionIcon: Icons.login,
      actionLabel: 'Sign in with GitHub',
      onAction: () async {
        final profile = await AuthDialog.show(context, 'github.com');
        if (profile == null) return;
        await ref
            .read(appSettingsProvider.notifier)
            .setAuthBinding(repo.id.value, profile.id);
        ref.invalidate(repoActiveProfileProvider(repo));
      },
    );
  }
}

class GitHubApiErrorView extends StatelessWidget {
  const GitHubApiErrorView({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is GitHubApiException
        ? error.toString()
        : 'GitHub request failed: $error';
    return AppEmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'GitHub request failed',
      message: message,
      actionIcon: Icons.refresh,
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}
