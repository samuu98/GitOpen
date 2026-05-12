import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../domain/diff/diff_hunk.dart';
import '../../domain/diff/diff_line.dart';
import '../../domain/diff/diff_spec.dart';
import '../../domain/diff/file_diff.dart';
import '../../domain/repositories/repo_location.dart';
import '../../domain/status/working_file_entry.dart';
import 'commit_compose.dart';

final _workingCopyStatusProvider =
    FutureProvider.family.autoDispose<List<WorkingFileEntry>, RepoLocation>((ref, repo) async {
  final git = ref.watch(gitReadOperationsProvider);
  final status = await git.getStatus(repo);
  return status.entries;
});

/// Provider that fetches the working-tree-vs-index diff for a single file.
/// Keyed by (repo, filePath). Returns null if the file has no diff entry.
final _fileDiffProvider = FutureProvider.family
    .autoDispose<FileDiff?, (RepoLocation, String)>((ref, args) async {
  final (repo, filePath) = args;
  final git = ref.read(gitReadOperationsProvider);
  final result = await git.getDiff(repo, const DiffSpecWorkingTreeVsIndex());
  try {
    return result.files.firstWhere((f) => f.path == filePath);
  } catch (_) {
    return null;
  }
});

/// Returns whether a [WorkingFileEntry] can have hunks expanded.
/// Untracked files have no index entry so git diff yields nothing useful.
bool _canExpandHunks(WorkingFileEntry entry) {
  return entry.workingTreeState != WorkingFileState.untracked &&
      entry.workingTreeState != WorkingFileState.ignored;
}

/// Builds a minimal unified-diff patch containing only the supplied hunks.
String buildPatchForHunks(String filePath, List<DiffHunk> hunks) {
  final buf = StringBuffer();
  buf.writeln('diff --git a/$filePath b/$filePath');
  buf.writeln('--- a/$filePath');
  buf.writeln('+++ b/$filePath');
  for (final h in hunks) {
    buf.writeln(h.header);
    for (final line in h.lines) {
      switch (line.kind) {
        case DiffLineKind.addition:
          buf.writeln('+${line.content}');
        case DiffLineKind.deletion:
          buf.writeln('-${line.content}');
        case DiffLineKind.context:
          buf.writeln(' ${line.content}');
      }
    }
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------

/// A file row in the working-copy list. For unstaged files that are not
/// untracked/binary it can be expanded to show individual hunks, each with
/// its own checkbox. When at least one hunk is checked, a "Stage selected
/// hunks" button appears.
class _FileRow extends ConsumerStatefulWidget {
  final RepoLocation repo;
  final WorkingFileEntry entry;
  final bool isStaged;
  const _FileRow({required this.repo, required this.entry, required this.isStaged});

  @override
  ConsumerState<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends ConsumerState<_FileRow> {
  bool _expanded = false;
  final Set<int> _checkedHunks = {};

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      if (!_expanded) _checkedHunks.clear();
    });
  }

  void _toggleHunk(int index) {
    setState(() {
      if (_checkedHunks.contains(index)) {
        _checkedHunks.remove(index);
      } else {
        _checkedHunks.add(index);
      }
    });
  }

  Future<void> _stageFile() async {
    final write = ref.read(gitWriteOperationsProvider);
    await write.stageFiles(widget.repo, [widget.entry.path]);
    ref.invalidate(_workingCopyStatusProvider(widget.repo));
  }

  Future<void> _unstageFile() async {
    final write = ref.read(gitWriteOperationsProvider);
    await write.unstageFiles(widget.repo, [widget.entry.path]);
    ref.invalidate(_workingCopyStatusProvider(widget.repo));
  }

  Future<void> _stageSelectedHunks(List<DiffHunk> allHunks) async {
    final selected = _checkedHunks.toList()..sort();
    final hunksToStage = selected.map((i) => allHunks[i]).toList();
    final patch = buildPatchForHunks(widget.entry.path, hunksToStage);
    final write = ref.read(gitWriteOperationsProvider);
    await write.stagePatch(widget.repo, patch);
    setState(() => _checkedHunks.clear());
    ref.invalidate(_workingCopyStatusProvider(widget.repo));
  }

  bool get _canExpand =>
      !widget.isStaged && _canExpandHunks(widget.entry);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFileRowHeader(),
        if (_expanded && _canExpand) _buildHunkSection(),
      ],
    );
  }

  Widget _buildFileRowHeader() {
    return InkWell(
      onTap: () async {
        if (widget.isStaged) {
          await _unstageFile();
        } else {
          await _stageFile();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          // Chevron for expansion (unstaged, non-untracked only)
          if (_canExpand)
            GestureDetector(
              onTap: _toggleExpanded,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: const Color(0xFF888892),
                ),
              ),
            )
          else
            const SizedBox(width: 18),
          // Stage/unstage checkbox
          Icon(widget.isStaged ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14, color: const Color(0xFFB8B8BC)),
          const SizedBox(width: 8),
          _StateBadge(state: widget.isStaged ? widget.entry.indexState : widget.entry.workingTreeState),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.entry.path,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12.5))),
          // "Stage selected hunks" button — shown when at least one hunk checked
          if (_checkedHunks.isNotEmpty)
            _buildStageSelectedButton(),
        ]),
      ),
    );
  }

  Widget _buildStageSelectedButton() {
    final diffAsync = ref.watch(_fileDiffProvider((widget.repo, widget.entry.path)));
    return diffAsync.maybeWhen(
      data: (fileDiff) {
        if (fileDiff == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 11),
            ),
            onPressed: () => _stageSelectedHunks(fileDiff.hunks),
            child: const Text('Stage selected hunks'),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _buildHunkSection() {
    final diffAsync = ref.watch(_fileDiffProvider((widget.repo, widget.entry.path)));
    return diffAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(left: 32, top: 4, bottom: 4),
        child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 1.5)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(left: 32, top: 2, bottom: 2),
        child: Text('Diff error: $e',
            style: const TextStyle(color: Color(0xFFC4314B), fontSize: 11)),
      ),
      data: (fileDiff) {
        if (fileDiff == null || fileDiff.isBinary || fileDiff.hunks.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < fileDiff.hunks.length; i++)
              _HunkRow(
                hunk: fileDiff.hunks[i],
                index: i,
                isChecked: _checkedHunks.contains(i),
                onToggle: () => _toggleHunk(i),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

/// A single hunk sub-row displayed below an expanded file row.
class _HunkRow extends StatelessWidget {
  final DiffHunk hunk;
  final int index;
  final bool isChecked;
  final VoidCallback onToggle;
  const _HunkRow({
    required this.hunk,
    required this.index,
    required this.isChecked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        color: const Color(0xFF1A1A1E),
        padding: const EdgeInsets.only(left: 32, right: 12, top: 3, bottom: 3),
        child: Row(children: [
          Icon(
            isChecked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 13,
            color: const Color(0xFF888892),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hunk.header,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6FA8DC),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

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
