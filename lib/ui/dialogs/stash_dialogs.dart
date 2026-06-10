import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/repo_revision.dart';
import '../../domain/refs/stash.dart';
import '../../domain/repositories/repo_location.dart';
import '../bottom_panel/diff_view.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import 'app_dialog.dart';
import 'confirm_dialog.dart';

/// Prompt for `git stash push`: optional message + include-untracked toggle.
class StashSaveDialog extends StatefulWidget {
  const StashSaveDialog({super.key});

  /// Returns `(message, includeUntracked)`, or null when cancelled.
  static Future<(String, bool)?> show(BuildContext context) =>
      showDialog<(String, bool)>(
        context: context,
        builder: (_) => const StashSaveDialog(),
      );

  @override
  State<StashSaveDialog> createState() => _StashSaveDialogState();
}

class _StashSaveDialogState extends State<StashSaveDialog> {
  final _ctl = TextEditingController();
  bool _includeUntracked = true;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, (_ctl.text.trim(), _includeUntracked));

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final typo = AppTypography.of(context);
    return AppDialog(
      title: 'Stash changes',
      width: 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctl,
            autofocus: true,
            style: typo.body.copyWith(color: palette.fg0),
            decoration:
                appInputDecoration(context, label: 'Message (optional)'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () =>
                setState(() => _includeUntracked = !_includeUntracked),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: _includeUntracked,
                    onChanged: (v) =>
                        setState(() => _includeUntracked = v ?? true),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Include untracked files',
                    style: typo.body.copyWith(color: palette.fg1)),
              ],
            ),
          ),
        ],
      ),
      actions: [
        AppButton.secondary(
            label: 'Cancel', onPressed: () => Navigator.pop(context)),
        AppButton.primary(label: 'Stash', onPressed: _submit),
      ],
    );
  }
}

/// Interactive stash manager: list on the left, diff preview on the right,
/// Apply / Pop / Drop per stash.
class StashManagerDialog extends ConsumerStatefulWidget {
  final RepoLocation repo;
  const StashManagerDialog({super.key, required this.repo});

  static Future<void> show(BuildContext context, RepoLocation repo) =>
      showDialog<void>(
        context: context,
        builder: (_) => StashManagerDialog(repo: repo),
      );

  @override
  ConsumerState<StashManagerDialog> createState() =>
      _StashManagerDialogState();
}

class _StashManagerDialogState extends ConsumerState<StashManagerDialog> {
  late Future<List<Stash>> _stashesFuture;
  Stash? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _stashesFuture =
        ref.read(gitReadOperationsProvider).getStashes(widget.repo);
  }

  Future<void> _run(Future<void> Function() op) async {
    setState(() => _busy = true);
    try {
      await op();
      refreshRepo(ref, widget.repo);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _selected = null;
          _reload();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final typo = AppTypography.of(context);
    return AppDialog(
      title: 'Stashes',
      width: 760,
      busy: _busy,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        height: 420,
        child: FutureBuilder<List<Stash>>(
          future: _stashesFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)));
            }
            final stashes = snap.data ?? const <Stash>[];
            if (stashes.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 28, color: palette.fg3),
                    const SizedBox(height: 8),
                    Text('No stashes',
                        style: typo.body.copyWith(color: palette.fg2)),
                  ],
                ),
              );
            }
            final selected = _selected != null &&
                    stashes.any((s) => s.index == _selected!.index)
                ? stashes.firstWhere((s) => s.index == _selected!.index)
                : stashes.first;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 280,
                  child: ListView.builder(
                    itemCount: stashes.length,
                    itemBuilder: (_, i) => _StashRow(
                      stash: stashes[i],
                      selected: stashes[i].index == selected.index,
                      enabled: !_busy,
                      onTap: () => setState(() => _selected = stashes[i]),
                      onApply: () => _run(() async {
                        await ref
                            .read(gitWriteOperationsProvider)
                            .stashApply(widget.repo, stashes[i].index);
                      }),
                      onPop: () => _run(() async {
                        await ref
                            .read(gitWriteOperationsProvider)
                            .stashPop(widget.repo, stashes[i].index);
                      }),
                      onDrop: () async {
                        final ok = await ConfirmDialog.show(
                          context,
                          title: 'Drop stash',
                          body:
                              'Drop stash@{${stashes[i].index}}? Its changes '
                              'will be lost.',
                          confirmLabel: 'Drop',
                          dangerous: true,
                        );
                        if (!ok) return;
                        await _run(() async {
                          await ref
                              .read(gitWriteOperationsProvider)
                              .stashDrop(widget.repo, stashes[i].index);
                        });
                      },
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: palette.border),
                // Stash commits' first parent is the HEAD they were created
                // on, so the standard commit-vs-parent diff shows exactly
                // the stashed changes.
                Expanded(
                  child: DiffView(repo: widget.repo, sha: selected.sha),
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

class _StashRow extends StatefulWidget {
  final Stash stash;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onApply;
  final VoidCallback onPop;
  final VoidCallback onDrop;

  const _StashRow({
    required this.stash,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onApply,
    required this.onPop,
    required this.onDrop,
  });

  @override
  State<_StashRow> createState() => _StashRowState();
}

class _StashRowState extends State<_StashRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final typo = AppTypography.of(context);
    final s = widget.stash;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          hoverColor: palette.bg3,
          child: Container(
            color: widget.selected ? palette.bgAccent : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('stash@{${s.index}}',
                        style: typo.monoSmall.copyWith(
                            color: palette.fg0, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (_hover && widget.enabled) ...[
                      _RowAction(
                          icon: Icons.download_outlined,
                          tooltip: 'Apply (keep stash)',
                          onTap: widget.onApply),
                      _RowAction(
                          icon: Icons.eject_outlined,
                          tooltip: 'Pop (apply and drop)',
                          onTap: widget.onPop),
                      _RowAction(
                          icon: Icons.delete_outline,
                          tooltip: 'Drop',
                          danger: true,
                          onTap: widget.onDrop),
                    ],
                  ],
                ),
                if (s.message.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    s.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: typo.bodySmall.copyWith(color: palette.fg2),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon,
              size: 14, color: danger ? palette.accentErr : palette.fg2),
        ),
      ),
    );
  }
}
