import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/repo_revision.dart';
import '../../domain/commits/commit_info.dart';
import '../../domain/repositories/repo_location.dart';
import '../bottom_panel/diff_view.dart';
import '../common/author_avatar.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import 'app_dialog.dart';
import 'confirm_dialog.dart';

/// History of a single file: commits that touched it on the left, the
/// file-scoped diff of the selected commit on the right. From here the file
/// can be restored to its content at any listed commit.
class FileHistoryDialog extends ConsumerStatefulWidget {
  final RepoLocation repo;
  final String path;

  const FileHistoryDialog({super.key, required this.repo, required this.path});

  static Future<void> show(
          BuildContext context, RepoLocation repo, String path) =>
      showDialog<void>(
        context: context,
        builder: (_) => FileHistoryDialog(repo: repo, path: path),
      );

  @override
  ConsumerState<FileHistoryDialog> createState() => _FileHistoryDialogState();
}

class _FileHistoryDialogState extends ConsumerState<FileHistoryDialog> {
  late final Future<List<CommitInfo>> _historyFuture;
  CommitInfo? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _historyFuture =
        ref.read(gitReadOperationsProvider).getFileHistory(widget.repo, widget.path);
  }

  Future<void> _restore(CommitInfo commit) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Restore file',
      body: 'Replace "${widget.path}" in the working tree with its content '
          'at ${commit.sha.short()}?\n\nThe change stays unstaged so you can '
          'review it before committing.',
      confirmLabel: 'Restore',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(gitWriteOperationsProvider)
          .restoreFileAt(widget.repo, commit.sha, [widget.path]);
      refreshRepo(ref, widget.repo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Restored ${widget.path} to ${commit.sha.short()} (unstaged).')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final typo = AppTypography.of(context);
    return AppDialog(
      title: 'File history',
      subtitle: widget.path,
      width: 860,
      busy: _busy,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        height: 460,
        child: FutureBuilder<List<CommitInfo>>(
          future: _historyFuture,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                  child: Text('Failed to load history: ${snap.error}',
                      style: typo.body.copyWith(color: palette.accentErr)));
            }
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)));
            }
            final commits = snap.data ?? const <CommitInfo>[];
            if (commits.isEmpty) {
              return Center(
                  child: Text('No commits found for this file.',
                      style: typo.body.copyWith(color: palette.fg2)));
            }
            final selected = _selected ?? commits.first;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 320,
                  child: ListView.builder(
                    itemCount: commits.length,
                    itemBuilder: (_, i) => _HistoryRow(
                      commit: commits[i],
                      selected: commits[i].sha == selected.sha,
                      onTap: () => setState(() => _selected = commits[i]),
                      onCopySha: () => Clipboard.setData(
                          ClipboardData(text: commits[i].sha.value)),
                      onRestore: _busy ? null : () => _restore(commits[i]),
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: palette.border),
                Expanded(
                  child: DiffView(
                    repo: widget.repo,
                    sha: selected.sha,
                    pathFilter: widget.path,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        AppButton.secondary(
            label: 'Close', onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}

class _HistoryRow extends StatefulWidget {
  final CommitInfo commit;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onCopySha;
  final VoidCallback? onRestore;

  const _HistoryRow({
    required this.commit,
    required this.selected,
    required this.onTap,
    required this.onCopySha,
    required this.onRestore,
  });

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final typo = AppTypography.of(context);
    final c = widget.commit;
    final date = c.author.when.toLocal();
    final dateLabel = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: palette.bg3,
          child: Container(
            color: widget.selected ? palette.bgAccent : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AuthorAvatar(
                        name: c.author.name, email: c.author.email, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        c.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.body.copyWith(color: palette.fg0),
                      ),
                    ),
                    if (_hover) ...[
                      Tooltip(
                        message: 'Copy SHA',
                        child: InkWell(
                          onTap: widget.onCopySha,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child:
                                Icon(Icons.copy, size: 13, color: palette.fg2),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Restore file to this commit',
                        child: InkWell(
                          onTap: widget.onRestore,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(Icons.settings_backup_restore,
                                size: 13, color: palette.accentCurrent),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${c.sha.short()}  ·  ${c.author.name}  ·  $dateLabel',
                  style: typo.monoSmall.copyWith(color: palette.fg2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
