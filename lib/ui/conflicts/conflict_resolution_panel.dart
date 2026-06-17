import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/conflicts/merge_editor_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:url_launcher/url_launcher.dart';

final AutoDisposeFutureProviderFamily<List<String>, RepoLocation>
    _conflictsProvider =
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
            if (op == InProgressOp.none || files.isEmpty) {
              return const SizedBox.shrink();
            }
            final opLabel = switch (op) {
              InProgressOp.merge => 'Merge',
              InProgressOp.cherryPick => 'Cherry-pick',
              InProgressOp.revert => 'Revert',
              InProgressOp.rebase => 'Rebase',
              _ => op.name,
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: palette.accentWarn.withValues(alpha: 0.15),
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(Icons.warning_amber,
                        color: palette.accentTag, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '$opLabel in progress — '
                      '${files.length} conflict${files.length == 1 ? "" : "s"}',
                      style: TextStyle(
                          color: palette.fg0,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final path in files)
                        ListTile(
                          leading: Icon(Icons.error_outline,
                              color: palette.accentErr, size: 18),
                          title: Text(path,
                              style: TextStyle(
                                  color: palette.fg0, fontSize: 12.5)),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            TextButton(
                              onPressed: () async {
                                await ref
                                    .read(gitActionsControllerProvider)
                                    .takeConflictSide(
                                      context,
                                      repo,
                                      path,
                                      ours: true,
                                    );
                                ref.invalidate(_conflictsProvider(repo));
                              },
                              child: const Text('Ours'),
                            ),
                            TextButton(
                              onPressed: () async {
                                await ref
                                    .read(gitActionsControllerProvider)
                                    .takeConflictSide(
                                      context,
                                      repo,
                                      path,
                                      ours: false,
                                    );
                                ref.invalidate(_conflictsProvider(repo));
                              },
                              child: const Text('Theirs'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _resolveInApp(context, ref, path),
                              child: const Text('Resolve'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _openInEditor(ref, repo.path, path),
                              child: const Text('Open'),
                            ),
                            TextButton(
                              onPressed: () async {
                                await ref
                                    .read(gitWriteOperationsProvider)
                                    .stageFiles(repo, [path]);
                                ref.invalidate(_conflictsProvider(repo));
                              },
                              child: const Text('Mark resolved'),
                            ),
                          ]),
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
                      onPressed: files.isEmpty
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

  /// Opens the in-app 3-way merge editor for [path]. On a successful save the
  /// editor stages the file, so we just refresh the conflicts list. If the
  /// file has no parseable markers the editor returns
  /// [MergeEditorResult.openExternal] and we fall back to the existing
  /// external-editor action.
  Future<void> _resolveInApp(
    BuildContext context,
    WidgetRef ref,
    String path,
  ) async {
    final result = await MergeEditorDialog.show(
      context,
      repo: repo,
      relativePath: path,
    );
    switch (result) {
      case MergeEditorResult.resolved:
        ref.invalidate(_conflictsProvider(repo));
      case MergeEditorResult.openExternal:
        await _openInEditor(ref, repo.path, path);
      case null:
        break;
    }
  }

  Future<void> _openInEditor(
    WidgetRef ref,
    String repoPath,
    String filePath,
  ) async {
    final settingsPath = ref.read(appSettingsProvider).externalEditorPath;
    final fullPath = '$repoPath/$filePath';
    if (settingsPath != null && settingsPath.isNotEmpty) {
      await ref
          .read(repoLauncherProvider)
          .openFileInEditor(settingsPath, fullPath);
    } else {
      await launchUrl(Uri.file(fullPath));
    }
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
