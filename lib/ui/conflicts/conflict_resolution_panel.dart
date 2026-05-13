import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../application/git/repo_state_provider.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';
import '../../domain/status/working_file_entry.dart';
import '../theme/app_palette.dart';

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
  final RepoLocation repo;
  const ConflictResolutionPanel({super.key, required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opAsync = ref.watch(repoStateProvider(repo));
    final filesAsync = ref.watch(_conflictsProvider(repo));
    final palette = AppPalette.of(context);
    return Container(
      color: palette.bg1,
      child: opAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Center(child: Text('$e')),
        data: (op) => filesAsync.when(
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
                              onPressed: () => _openInEditor(ref, repo.path, path),
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
                      onPressed: () => _abort(ref, op),
                      child: const Text('Abort'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed:
                          files.isEmpty ? () => _continue(ref, op) : null,
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

  Future<void> _openInEditor(WidgetRef ref, String repoPath, String filePath) async {
    final settingsPath = ref.read(appSettingsProvider).externalEditorPath;
    if (settingsPath != null && settingsPath.isNotEmpty) {
      final fullPath = '$repoPath/$filePath';
      await Process.run(settingsPath, [fullPath]);
    } else {
      final url = Uri.file('$repoPath/$filePath');
      await launchUrl(url);
    }
  }

  Future<void> _abort(WidgetRef ref, InProgressOp op) async {
    final write = ref.read(gitWriteOperationsProvider);
    if (op == InProgressOp.merge) await write.mergeAbort(repo);
    if (op == InProgressOp.cherryPick) await write.cherryPickAbort(repo);
    if (op == InProgressOp.revert) await write.revertAbort(repo);
    ref.invalidate(repoStateProvider(repo));
  }

  Future<void> _continue(WidgetRef ref, InProgressOp op) async {
    final write = ref.read(gitWriteOperationsProvider);
    if (op == InProgressOp.merge) await write.mergeContinue(repo);
    if (op == InProgressOp.cherryPick) await write.cherryPickContinue(repo);
    if (op == InProgressOp.revert) await write.revertContinue(repo);
    ref.invalidate(repoStateProvider(repo));
  }
}
