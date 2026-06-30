import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/conflicts/inline_merge_resolver.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:url_launcher/url_launcher.dart';

final _conflictsProvider =
    FutureProvider.family.autoDispose<List<String>, RepoLocation>(
        (ref, repo) async {
  final git = ref.watch(gitReadOperationsProvider);
  final status = await git.getStatus(repo);
  return status.entries
      .where((e) => e.workingTreeState == WorkingFileState.conflicted)
      .map((e) => e.path)
      .toList();
});

class ConflictResolutionPanel extends ConsumerWidget {
  const ConflictResolutionPanel({required this.repo, super.key});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opAsync = ref.watch(repoStateProvider(repo));
    final filesAsync = ref.watch(_conflictsProvider(repo));
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: palette.bg1,
      child: opAsync.when(
        // Keep the conflict panel visible during background reloads.
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Center(child: Text('$e')),
        data: (op) => filesAsync.when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Center(child: Text('$e')),
          data: (files) {
            if (op == InProgressOp.none) return const SizedBox.shrink();
            final opLabel = switch (op) {
              InProgressOp.merge => 'Merge',
              InProgressOp.cherryPick => 'Cherry-pick',
              InProgressOp.revert => 'Revert',
              InProgressOp.rebase => 'Rebase',
              _ => op.name,
            };
            final allResolved = files.isEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  opLabel: opLabel,
                  conflictCount: files.length,
                  palette: palette,
                ),
                Expanded(
                  child: allResolved
                      ? _AllResolved(opLabel: opLabel, palette: palette)
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          children: [
                            for (final path in files)
                              _ConflictCard(
                                key: ValueKey(path),
                                repo: repo,
                                path: path,
                                initiallyExpanded: files.length == 1,
                                onChanged: () =>
                                    ref.invalidate(_conflictsProvider(repo)),
                              ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    OutlinedButton(
                      onPressed: () => _abort(context, ref, op),
                      child: const Text('Abort'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: allResolved
                          ? () => _continue(context, ref, op)
                          : null,
                      child: const Text('Continue'),
                    ),
                  ]),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _abort(
    BuildContext context,
    WidgetRef ref,
    InProgressOp op,
  ) async {
    final actions = ref.read(gitActionsControllerProvider);
    switch (op) {
      case InProgressOp.merge:
        await actions.mergeAbort(context, repo);
      case InProgressOp.cherryPick:
        await actions.cherryPickAbort(context, repo);
      case InProgressOp.revert:
        await actions.revertAbort(context, repo);
      case InProgressOp.rebase:
        await actions.rebaseAbort(context, repo);
      case InProgressOp.none:
        break;
    }
  }

  Future<void> _continue(
    BuildContext context,
    WidgetRef ref,
    InProgressOp op,
  ) async {
    final actions = ref.read(gitActionsControllerProvider);
    switch (op) {
      case InProgressOp.merge:
        await actions.mergeContinue(context, repo);
      case InProgressOp.cherryPick:
        await actions.cherryPickContinue(context, repo);
      case InProgressOp.revert:
        await actions.revertContinue(context, repo);
      case InProgressOp.rebase:
        await actions.rebaseContinue(context, repo);
      case InProgressOp.none:
        break;
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.opLabel,
    required this.conflictCount,
    required this.palette,
  });

  final String opLabel;
  final int conflictCount;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final resolved = conflictCount == 0;
    return Container(
      color: (resolved ? palette.accentCurrent : palette.accentWarn)
          .withValues(alpha: 0.15),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Icon(
          resolved ? Icons.check_circle_outline : Icons.warning_amber,
          color: resolved ? palette.accentCurrent : palette.accentTag,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          resolved
              ? '$opLabel ready — all conflicts resolved'
              : '$opLabel in progress — '
                  '$conflictCount conflict${conflictCount == 1 ? "" : "s"}',
          style: TextStyle(color: palette.fg0, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

/// Shown once every file is staged but the operation isn't committed yet, so
/// the user can still reach "Continue" (previously the panel hid itself here,
/// stranding an in-progress merge with no way forward).
class _AllResolved extends StatelessWidget {
  const _AllResolved({required this.opLabel, required this.palette});

  final String opLabel;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: palette.accentCurrent, size: 36),
            const SizedBox(height: 12),
            Text(
              'All conflicts resolved.',
              style: TextStyle(
                color: palette.fg0,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Click Continue to finish the $opLabel.',
              style: TextStyle(color: palette.fg2, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single conflicted file as an expandable card: the header row carries
/// whole-file quick actions (take ours/theirs, open externally, mark resolved);
/// expanding reveals the inline 3-way resolver.
class _ConflictCard extends ConsumerStatefulWidget {
  const _ConflictCard({
    required this.repo,
    required this.path,
    required this.initiallyExpanded,
    required this.onChanged,
    super.key,
  });

  final RepoLocation repo;
  final String path;
  final bool initiallyExpanded;

  /// Called whenever this file's conflict state may have changed (a side was
  /// taken, it was marked resolved, or the inline resolver saved it), so the
  /// host can refresh the conflict list.
  final VoidCallback onChanged;

  @override
  ConsumerState<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends ConsumerState<_ConflictCard> {
  late bool _expanded = widget.initiallyExpanded;
  bool _busy = false;

  Future<void> _takeSide({required bool ours}) async {
    setState(() => _busy = true);
    await ref.read(gitActionsControllerProvider).takeConflictSide(
          context,
          widget.repo,
          widget.path,
          ours: ours,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged();
  }

  Future<void> _markResolved() async {
    setState(() => _busy = true);
    await ref.read(gitWriteOperationsProvider).stageFiles(
      widget.repo,
      [widget.path],
    );
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged();
  }

  Future<void> _openInEditor() async {
    final settingsPath = ref.read(appSettingsProvider).externalEditorPath;
    final fullPath = '${widget.repo.path}/${widget.path}';
    if (settingsPath != null && settingsPath.isNotEmpty) {
      await ref
          .read(repoLauncherProvider)
          .openFileInEditor(settingsPath, fullPath);
    } else {
      await launchUrl(Uri.file(fullPath));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: palette.bg2,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: palette.fg2,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.error_outline,
                      color: palette.accentErr, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.path,
                      style: TextStyle(color: palette.fg0, fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: palette.fg3,
                        ),
                      ),
                    )
                  else ...[
                    _QuickAction(
                      label: 'Ours',
                      onPressed: () => _takeSide(ours: true),
                    ),
                    _QuickAction(
                      label: 'Theirs',
                      onPressed: () => _takeSide(ours: false),
                    ),
                    _QuickAction(label: 'Open', onPressed: _openInEditor),
                    _QuickAction(
                      label: 'Mark resolved',
                      onPressed: _markResolved,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, thickness: 1, color: palette.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: InlineMergeResolver(
                repo: widget.repo,
                relativePath: widget.path,
                onResolved: widget.onChanged,
                onOpenExternal: _openInEditor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
