import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/git/git_result.dart';
import '../../application/git/merge_outcome.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';
import '../theme/app_palette.dart';
import 'app_dialog.dart';

/// Asks the user which merge strategy to use before kicking off a merge,
/// while running a dry-run conflict check in the background so the user
/// sees up front whether the merge is going to be clean.
class MergeDialog extends ConsumerStatefulWidget {
  final RepoLocation repo;
  final String sourceRef;
  final String targetRef;

  const MergeDialog({
    super.key,
    required this.repo,
    required this.sourceRef,
    required this.targetRef,
  });

  /// Returns the chosen [MergeStrategy], or `null` if the user cancelled.
  static Future<MergeStrategy?> show(
    BuildContext context, {
    required RepoLocation repo,
    required String sourceRef,
    required String targetRef,
  }) {
    return showDialog<MergeStrategy>(
      context: context,
      builder: (_) => MergeDialog(
        repo: repo,
        sourceRef: sourceRef,
        targetRef: targetRef,
      ),
    );
  }

  @override
  ConsumerState<MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends ConsumerState<MergeDialog> {
  MergeStrategy _strategy = MergeStrategy.defaultStrategy;
  late final Future<GitResult<MergePreview>> _previewFuture;

  @override
  void initState() {
    super.initState();
    _previewFuture =
        ref.read(gitWriteOperationsProvider).previewMerge(widget.repo, widget.sourceRef);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AppDialog(
      title: 'Merge Branch',
      subtitle: 'Merge branch into another one',
      width: 520,
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LeadingIcon(palette: palette),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _RefRow(label: 'Merge:', ref: widget.sourceRef, palette: palette),
                const SizedBox(height: 8),
                _RefRow(label: 'Into:', ref: widget.targetRef, palette: palette),
                const SizedBox(height: 16),
                _StrategyRow(
                  value: _strategy,
                  onChanged: (s) => setState(() => _strategy = s),
                  palette: palette,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Expanded(
          child: _PreviewBanner(future: _previewFuture, palette: palette),
        ),
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, null),
        ),
        AppButton.primary(
          label: 'Merge',
          onPressed: () => Navigator.pop(context, _strategy),
          autofocus: true,
        ),
      ],
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  final AppPalette palette;
  const _LeadingIcon({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: palette.accentRemote.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(
          color: palette.accentRemote.withValues(alpha: 0.5),
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.call_merge, color: palette.accentRemote, size: 28),
    );
  }
}

class _RefRow extends StatelessWidget {
  final String label;
  final String ref;
  final AppPalette palette;
  const _RefRow({required this.label, required this.ref, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(
              color: palette.fg2,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Icon(Icons.alt_route, size: 14, color: palette.fg2),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            ref,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.fg0,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

class _StrategyRow extends StatelessWidget {
  final MergeStrategy value;
  final ValueChanged<MergeStrategy> onChanged;
  final AppPalette palette;
  const _StrategyRow({
    required this.value,
    required this.onChanged,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            'Merge Option:',
            style: TextStyle(
              color: palette.fg2,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: palette.bg1,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<MergeStrategy>(
                value: value,
                isExpanded: true,
                dropdownColor: palette.bg2,
                style: TextStyle(color: palette.fg0, fontSize: 12.5),
                iconEnabledColor: palette.fg2,
                items: MergeStrategy.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: _StrategyEntry(strategy: s, palette: palette),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StrategyEntry extends StatelessWidget {
  final MergeStrategy strategy;
  final AppPalette palette;
  const _StrategyEntry({required this.strategy, required this.palette});

  @override
  Widget build(BuildContext context) {
    final (title, description, flag) = _strategyLabels(strategy);
    return Row(
      children: [
        Text(title, style: TextStyle(color: palette.fg0, fontSize: 12.5)),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            description,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.fg2, fontSize: 12),
          ),
        ),
        if (flag != null) ...[
          const SizedBox(width: 12),
          Text(
            flag,
            style: TextStyle(
              color: palette.fg3,
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }
}

/// Resolves the short name of the branch HEAD points at (e.g. "develop"),
/// or `null` if HEAD is detached. Reads from the cached [branchesProvider]
/// so the dialog opens without an extra git call when the data is already
/// loaded for the sidebar.
Future<String?> currentBranchName(WidgetRef ref, RepoLocation repo) async {
  final branches = await ref.read(branchesProvider(repo).future);
  for (final b in branches) {
    if (b.isCurrent && !b.isRemote) return b.name;
  }
  return null;
}

(String, String, String?) _strategyLabels(MergeStrategy s) => switch (s) {
      MergeStrategy.defaultStrategy => ('Default', 'Fast-forward if possible', null),
      MergeStrategy.noFF => ('No Fast-Forward', 'Always create a merge commit', '--no-ff'),
      MergeStrategy.squash => ('Squash', 'Squash merge', '--squash'),
      MergeStrategy.noCommit => ("Don't Commit", 'Merge without commit', '--no-commit'),
    };

class _PreviewBanner extends StatelessWidget {
  final Future<GitResult<MergePreview>> future;
  final AppPalette palette;
  const _PreviewBanner({required this.future, required this.palette});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GitResult<MergePreview>>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Row(children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: palette.fg3),
            ),
            const SizedBox(width: 8),
            Text('Checking for conflicts…',
                style: TextStyle(color: palette.fg2, fontSize: 12)),
          ]);
        }
        final result = snap.data!;
        if (result case GitFailure(:final message)) {
          return Row(children: [
            Icon(Icons.info_outline, size: 16, color: palette.fg2),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Conflict check unavailable: $message',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.fg2, fontSize: 12),
              ),
            ),
          ]);
        }
        final preview = (result as GitSuccess<MergePreview>).value;
        if (preview is MergePreviewClean) {
          return Row(children: [
            Icon(Icons.check_circle_outline,
                size: 16, color: palette.accentCurrent),
            const SizedBox(width: 8),
            Text('Merge will apply cleanly',
                style: TextStyle(color: palette.fg1, fontSize: 12)),
          ]);
        }
        final conflicts = (preview as MergePreviewConflicts).conflictedPaths;
        final n = conflicts.length;
        return Tooltip(
          message: conflicts.isEmpty ? '' : conflicts.take(20).join('\n'),
          waitDuration: const Duration(milliseconds: 400),
          child: Row(children: [
            Icon(Icons.warning_amber, size: 16, color: palette.accentTag),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                n == 0
                    ? 'Merge will cause conflicts'
                    : 'Merge will cause conflicts in $n file${n == 1 ? '' : 's'}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.fg1, fontSize: 12),
              ),
            ),
          ]),
        );
      },
    );
  }
}
