import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';
import '../../domain/status/working_file_entry.dart';
import 'commit_compose.dart';

final _workingCopyStatusProvider =
    FutureProvider.family.autoDispose<List<WorkingFileEntry>, RepoLocation>((ref, repo) async {
  final git = ref.watch(gitReadOperationsProvider);
  final status = await git.getStatus(repo);
  return status.entries;
});

class WorkingCopyPanel extends ConsumerWidget {
  final RepoLocation repo;
  const WorkingCopyPanel({super.key, required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_workingCopyStatusProvider(repo));
    return Container(
      color: const Color(0xFF1F1F23),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Color(0xFFC4314B)))),
        data: (entries) {
          final unstaged = entries.where((e) =>
              e.workingTreeState != WorkingFileState.unmodified).toList();
          final staged = entries.where((e) =>
              e.indexState != WorkingFileState.unmodified).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _FileList(
                repo: repo, unstaged: unstaged, staged: staged,
              )),
              const Divider(height: 1, color: Color(0xFF313137)),
              CommitCompose(repo: repo),
            ],
          );
        },
      ),
    );
  }
}

class _FileList extends ConsumerWidget {
  final RepoLocation repo;
  final List<WorkingFileEntry> unstaged;
  final List<WorkingFileEntry> staged;
  const _FileList({required this.repo, required this.unstaged, required this.staged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(children: [
      _Header(
        title: 'Unstaged (${unstaged.length})',
        action: 'Stage all',
        onAction: unstaged.isEmpty ? null : () async {
          await ref.read(gitWriteOperationsProvider).stageFiles(repo, unstaged.map((e) => e.path).toList());
          ref.invalidate(_workingCopyStatusProvider(repo));
        },
      ),
      for (final e in unstaged) _FileRow(repo: repo, entry: e, isStaged: false),
      _Header(
        title: 'Staged (${staged.length})',
        action: 'Unstage all',
        onAction: staged.isEmpty ? null : () async {
          await ref.read(gitWriteOperationsProvider).unstageFiles(repo, staged.map((e) => e.path).toList());
          ref.invalidate(_workingCopyStatusProvider(repo));
        },
      ),
      for (final e in staged) _FileRow(repo: repo, entry: e, isStaged: true),
    ]);
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const _Header({required this.title, this.action, this.onAction});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF25252A),
      child: Row(children: [
        Text(title, style: const TextStyle(color: Color(0xFFB8B8BC), fontSize: 11.5, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (action != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ]),
    );
  }
}

class _FileRow extends ConsumerWidget {
  final RepoLocation repo;
  final WorkingFileEntry entry;
  final bool isStaged;
  const _FileRow({required this.repo, required this.entry, required this.isStaged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final write = ref.read(gitWriteOperationsProvider);
    return InkWell(
      onTap: () async {
        if (isStaged) {
          await write.unstageFiles(repo, [entry.path]);
        } else {
          await write.stageFiles(repo, [entry.path]);
        }
        ref.invalidate(_workingCopyStatusProvider(repo));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          Icon(isStaged ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14, color: const Color(0xFFB8B8BC)),
          const SizedBox(width: 8),
          _StateBadge(state: isStaged ? entry.indexState : entry.workingTreeState),
          const SizedBox(width: 8),
          Expanded(child: Text(entry.path,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12.5))),
        ]),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final WorkingFileState state;
  const _StateBadge({required this.state});
  @override
  Widget build(BuildContext context) {
    final (label, color) = _info(state);
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
  (String, Color) _info(WorkingFileState s) {
    switch (s) {
      case WorkingFileState.added: return ('A', const Color(0xFF4EC9B0));
      case WorkingFileState.modified: return ('M', const Color(0xFFD7BA7D));
      case WorkingFileState.deleted: return ('D', const Color(0xFFC4314B));
      case WorkingFileState.renamed: return ('R', const Color(0xFF6FA8DC));
      case WorkingFileState.untracked: return ('?', const Color(0xFF888892));
      case WorkingFileState.conflicted: return ('U', const Color(0xFFF48771));
      case WorkingFileState.ignored: return ('I', const Color(0xFF5D5D65));
      default: return ('', Colors.transparent);
    }
  }
}
