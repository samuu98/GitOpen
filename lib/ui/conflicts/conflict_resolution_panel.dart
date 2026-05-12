import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../application/git/repo_state_provider.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';
import '../../domain/status/working_file_entry.dart';

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
    return Container(
      color: const Color(0xFF1F1F23),
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: const Color(0xFF3D2A1A),
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.warning_amber,
                        color: Color(0xFFD7BA7D), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${op == InProgressOp.merge ? "Merge" : "Cherry-pick"} in progress — '
                      '${files.length} conflict${files.length == 1 ? "" : "s"}',
                      style: const TextStyle(
                          color: Color(0xFFD4D4D4),
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final path in files)
                        ListTile(
                          leading: const Icon(Icons.error_outline,
                              color: Color(0xFFC4314B), size: 18),
                          title: Text(path,
                              style: const TextStyle(
                                  color: Color(0xFFD4D4D4), fontSize: 12.5)),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            TextButton(
                              onPressed: () => _openInEditor(repo.path, path),
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

  Future<void> _openInEditor(String repoPath, String filePath) async {
    final url = Uri.file('$repoPath/$filePath');
    await launchUrl(url);
  }

  Future<void> _abort(WidgetRef ref, InProgressOp op) async {
    final write = ref.read(gitWriteOperationsProvider);
    if (op == InProgressOp.merge) await write.mergeAbort(repo);
    if (op == InProgressOp.cherryPick) await write.cherryPickAbort(repo);
    ref.invalidate(repoStateProvider(repo));
  }

  Future<void> _continue(WidgetRef ref, InProgressOp op) async {
    final write = ref.read(gitWriteOperationsProvider);
    if (op == InProgressOp.merge) await write.mergeContinue(repo);
    if (op == InProgressOp.cherryPick) await write.cherryPickContinue(repo);
    ref.invalidate(repoStateProvider(repo));
  }
}
