import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git_lfs/git_lfs_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/lfs/lfs_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Git LFS daily-driver view: install state, tracked patterns, stored
/// files, and the fetch/pull/push sync actions.
class LfsPanel extends ConsumerWidget {
  const LfsPanel({required this.repo, super.key});

  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(gitLfsStatusProvider(repo));
    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _LfsError(message: '$e'),
      data: (status) {
        if (!status.isInstalled) {
          return const _LfsNotInstalled();
        }
        if (!status.isRepoConfigured) {
          return _LfsSetup(repo: repo, status: status);
        }
        return _LfsReady(repo: repo, status: status);
      },
    );
  }
}

class _LfsError extends StatelessWidget {
  const _LfsError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Text(
        'Git LFS error: $message',
        style: TextStyle(color: palette.accentErr, fontSize: 12.5),
      ),
    );
  }
}

class _LfsNotInstalled extends StatelessWidget {
  const _LfsNotInstalled();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.storage_outlined,
      title: 'Git LFS is not installed',
      message: 'Install git-lfs from git-lfs.com, then reopen this view.',
    );
  }
}

class _LfsSetup extends ConsumerWidget {
  const _LfsSetup({required this.repo, required this.status});
  final RepoLocation repo;
  final GitLfsStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppEmptyState(
      icon: Icons.download_done,
      title: 'Git LFS is available',
      message:
          'Git LFS ${status.version ?? ''} is available but not set up in '
          'this repository.',
      actionIcon: Icons.download_done,
      actionLabel: 'Install in repo',
      onAction: () =>
          ref.read(lfsActionsControllerProvider).installLocal(context, repo),
    );
  }
}

class _LfsReady extends ConsumerWidget {
  const _LfsReady({required this.repo, required this.status});
  final RepoLocation repo;
  final GitLfsStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final controller = ref.read(lfsActionsControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: palette.bg2,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.storage_outlined, size: 14, color: palette.fg2),
              const SizedBox(width: 6),
              Text(
                'Git LFS ${status.version ?? ''}',
                style: TextStyle(
                  color: palette.fg1,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _ActionButton(
                label: 'Fetch',
                icon: Icons.cloud_download_outlined,
                onPressed: () => controller.fetch(context, repo),
              ),
              const SizedBox(width: 4),
              _ActionButton(
                label: 'Pull',
                icon: Icons.south,
                onPressed: () => controller.pull(context, repo),
              ),
              const SizedBox(width: 4),
              _ActionButton(
                label: 'Push',
                icon: Icons.north,
                onPressed: () => controller.push(context, repo),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _TrackedPatternsSection(repo: repo)),
              VerticalDivider(width: 1, color: palette.bg3),
              Expanded(flex: 2, child: _LfsFilesSection(repo: repo)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: palette.fg1,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 24),
        textStyle: const TextStyle(fontSize: 11.5),
      ),
      icon: Icon(icon, size: 13),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _TrackedPatternsSection extends ConsumerWidget {
  const _TrackedPatternsSection({required this.repo});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final patternsAsync = ref.watch(gitLfsTrackedPatternsProvider(repo));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
          child: Row(
            children: [
              Text(
                'Tracked patterns',
                style: TextStyle(
                  color: palette.fg2,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              AppIconButton(
                icon: Icons.add,
                tooltip: 'Add pattern',
                onPressed: () => _addPattern(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: patternsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _LfsError(message: '$e'),
            data: (patterns) => patterns.isEmpty
                ? const AppEmptyState(
                    icon: Icons.label_off_outlined,
                    title: 'No tracked patterns',
                    message: 'Track a file pattern to store it with Git LFS.',
                  )
                : ListView.builder(
                    itemCount: patterns.length,
                    itemBuilder: (context, i) =>
                        _PatternRow(repo: repo, pattern: patterns[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _addPattern(BuildContext context, WidgetRef ref) async {
    final pattern = await showDialog<String>(
      context: context,
      builder: (context) => const _AddPatternDialog(),
    );
    if (pattern == null || pattern.isEmpty || !context.mounted) return;
    await ref.read(lfsActionsControllerProvider).track(context, repo, pattern);
  }
}

class _AddPatternDialog extends StatefulWidget {
  const _AddPatternDialog();

  @override
  State<_AddPatternDialog> createState() => _AddPatternDialogState();
}

class _AddPatternDialogState extends State<_AddPatternDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Track pattern with Git LFS'),
      content: TextField(
        key: const Key('lfs-pattern-input'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '*.psd'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Track'),
        ),
      ],
    );
  }
}

class _PatternRow extends ConsumerWidget {
  const _PatternRow({required this.repo, required this.pattern});
  final RepoLocation repo;
  final GitLfsTrackedPattern pattern;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: pattern.attributes,
              child: Text(
                pattern.pattern,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.fg1,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.close,
            tooltip: 'Untrack ${pattern.pattern}',
            onPressed: () => ref
                .read(lfsActionsControllerProvider)
                .untrack(context, repo, pattern.pattern),
          ),
        ],
      ),
    );
  }
}

class _LfsFilesSection extends ConsumerWidget {
  const _LfsFilesSection({required this.repo});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final filesAsync = ref.watch(gitLfsFilesProvider(repo));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Text(
            'LFS files',
            style: TextStyle(
              color: palette.fg2,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: filesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _LfsError(message: '$e'),
            data: (files) => files.isEmpty
                ? const AppEmptyState(
                    icon: Icons.folder_off_outlined,
                    title: 'No LFS files in this repository',
                    message:
                        'Files matching tracked patterns will appear here.',
                  )
                : ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (context, i) => _FileRow(file: files[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});
  final GitLfsFile file;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 13, color: palette.fg3),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: file.oid,
              child: Text(
                file.path,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.fg1, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            file.sizeLabel,
            style: TextStyle(color: palette.fg3, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
