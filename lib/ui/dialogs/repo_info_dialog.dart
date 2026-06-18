import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/remote_web_url.dart';
import 'package:gitopen/application/git_lfs/git_lfs_models.dart';
import 'package:gitopen/application/main_view_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:url_launcher/url_launcher.dart';

/// Read-only panel for the active repo: local path, origin URL, and the
/// effective git identity, each with copy / open-folder / open-in-browser.
class RepoInfoDialog extends ConsumerWidget {
  const RepoInfoDialog({required this.repo, super.key});
  final RepoLocation repo;

  static Future<void> show(BuildContext context, {required RepoLocation repo}) {
    return showDialog<void>(
      context: context,
      builder: (_) => RepoInfoDialog(repo: repo),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final info = ref.watch(repoInfoProvider(repo));
    final lfsAsync = ref.watch(gitLfsStatusProvider(repo));
    return AppDialog(
      title: 'Repository',
      content: info.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (_, _) => Text(
          'Could not read repository info.',
          style: TextStyle(color: palette.fg2, fontSize: 12.5),
        ),
        data: (i) {
          final identity = (i.userName == null && i.userEmail == null)
              ? null
              : '${i.userName ?? '?'} <${i.userEmail ?? '?'}>';
          final webUrl =
              i.originUrl == null ? null : remoteWebUrl(i.originUrl!);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                label: 'Local path',
                value: i.path,
                actions: [
                  _CopyButton(value: i.path),
                  _ActionButton(
                    icon: Icons.folder_open,
                    tooltip: 'Open folder',
                    onTap: () async {
                      try {
                        await ref
                            .read(repoLauncherProvider)
                            .revealInFiles(repo);
                      } on Object catch (e) {
                        if (context.mounted) {
                          _snack(context, 'Could not open folder: $e');
                        }
                      }
                    },
                  ),
                ],
              ),
              _InfoRow(
                label: 'Remote (origin)',
                value: i.originUrl ?? 'No remote',
                muted: i.originUrl == null,
                actions: [
                  if (i.originUrl != null) _CopyButton(value: i.originUrl!),
                  if (webUrl != null)
                    _ActionButton(
                      icon: Icons.open_in_new,
                      tooltip: 'Open in browser',
                      onTap: () => launchUrl(
                        Uri.parse(webUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                ],
              ),
              _InfoRow(
                label: 'Git user',
                value: identity ?? 'Not set',
                muted: identity == null,
                actions: [
                  if (identity != null) _CopyButton(value: identity),
                ],
              ),
              _InfoRow(
                label: 'Git LFS',
                value: _lfsLabel(lfsAsync.value),
                muted:
                    !(lfsAsync.value?.isRepoConfigured ?? false),
                actions: [
                  _ActionButton(
                    icon: Icons.chevron_right,
                    tooltip: 'Open Git LFS',
                    onTap: () {
                      ref.read(mainViewProvider.notifier).state =
                          MainView.lfs;
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ],
          );
        },
      ),
      actions: [
        AppButton.secondary(
          label: 'Close',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

String _lfsLabel(GitLfsStatus? status) {
  if (status == null) return '…';
  if (!status.isInstalled) return 'Not installed';
  if (status.isRepoConfigured) return 'Configured';
  if (status.hasAttributes) return 'Tracked (not initialized)';
  return 'Not used';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.actions,
    this.muted = false,
  });
  final String label;
  final String value;
  final List<Widget> actions;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: palette.fg2, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted ? palette.fg3 : palette.fg0,
                fontSize: 12.5,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    return _ActionButton(
      icon: Icons.copy_outlined,
      tooltip: 'Copy',
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) _snack(context, 'Copied');
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return IconButton(
      icon: Icon(icon, size: 15, color: palette.fg2),
      tooltip: tooltip,
      splashRadius: 16,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      onPressed: onTap,
    );
  }
}
