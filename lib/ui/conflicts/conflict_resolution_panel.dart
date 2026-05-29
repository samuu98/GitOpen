import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../../application/git/repo_state_provider.dart';
import '../../application/providers.dart';
import '../../application/repo_revision.dart';
import '../../domain/repositories/repo_location.dart';
import '../../domain/status/working_file_entry.dart';
import '../theme/app_palette.dart';

final _conflictsProvider =
    FutureProvider.family.autoDispose<List<String>, RepoLocation>(
        (ref, repo) async {
  ref.watch(repoRevisionProvider(repo));
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
            // The parent only mounts this panel while an operation is in
            // progress; an empty conflict list does NOT mean "done" — it
            // means every conflict has been resolved and we are now ready to
            // run `--continue`.  Only collapse when there is genuinely no
            // operation in flight.
            if (op == InProgressOp.none) {
              return const SizedBox.shrink();
            }
            final allResolved = files.isEmpty;
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
                  color: (allResolved
                          ? palette.accentCurrent
                          : palette.accentWarn)
                      .withValues(alpha: 0.15),
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(
                        allResolved
                            ? Icons.check_circle_outline
                            : Icons.warning_amber,
                        color: allResolved
                            ? palette.accentCurrent
                            : palette.accentTag,
                        size: 16),
                    const SizedBox(width: 8),
                    Text(
                      allResolved
                          ? '$opLabel — all conflicts resolved, ready to continue'
                          : '$opLabel in progress — '
                              '${files.length} conflict${files.length == 1 ? "" : "s"}',
                      style: TextStyle(
                          color: palette.fg0,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
                Expanded(
                  child: allResolved
                      ? Center(
                          child: Text(
                            'No remaining conflicts.',
                            style: TextStyle(color: palette.fg2),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final path in files)
                              ListTile(
                                leading: Icon(Icons.error_outline,
                                    color: palette.accentErr, size: 18),
                                title: Text(path,
                                    style: TextStyle(
                                        color: palette.fg0, fontSize: 12.5)),
                                trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton(
                                        onPressed: () => _openInEditor(
                                            ref, repo.path, path),
                                        child: const Text('Open'),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          await ref
                                              .read(gitWriteOperationsProvider)
                                              .stageFiles(repo, [path]);
                                          ref.invalidate(
                                              _conflictsProvider(repo));
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
                          allResolved ? () => _continue(ref, op) : null,
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
    final fullPath = p.join(repoPath, filePath);
    if (settingsPath != null && settingsPath.isNotEmpty) {
      await Process.run(settingsPath, [fullPath]);
    } else {
      await launchUrl(Uri.file(fullPath));
    }
  }

  Future<void> _abort(WidgetRef ref, InProgressOp op) async {
    final write = ref.read(gitWriteOperationsProvider);
    if (op == InProgressOp.merge) await write.mergeAbort(repo);
    if (op == InProgressOp.cherryPick) await write.cherryPickAbort(repo);
    if (op == InProgressOp.revert) await write.revertAbort(repo);
    if (op == InProgressOp.rebase) await write.rebaseAbort(repo);
    ref.invalidate(repoStateProvider(repo));
  }

  Future<void> _continue(WidgetRef ref, InProgressOp op) async {
    final write = ref.read(gitWriteOperationsProvider);
    if (op == InProgressOp.merge) await write.mergeContinue(repo);
    if (op == InProgressOp.cherryPick) await write.cherryPickContinue(repo);
    if (op == InProgressOp.revert) await write.revertContinue(repo);
    if (op == InProgressOp.rebase) await write.rebaseContinue(repo);
    ref.invalidate(repoStateProvider(repo));
  }
}
