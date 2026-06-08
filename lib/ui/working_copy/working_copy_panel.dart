import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/bottom_panel/diff_syntax.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/commit_compose.dart';

/// Discards working-tree changes for the supplied entries.
///
/// Untracked files cannot be checkout-restored, so they go through
/// `git clean`; tracked files use `git checkout -- <paths>`. Returns true
/// when the operation completed without errors.
Future<bool> _discardEntries(
  WidgetRef ref,
  RepoLocation repo,
  List<WorkingFileEntry> entries,
) async {
  final untracked = <String>[];
  final tracked = <String>[];
  for (final e in entries) {
    if (e.workingTreeState == WorkingFileState.untracked) {
      untracked.add(e.path);
    } else {
      tracked.add(e.path);
    }
  }
  final write = ref.read(gitWriteOperationsProvider);
  final r1 = await write.discardChanges(repo, tracked);
  final r2 = await write.cleanUntracked(repo, untracked);
  ref.invalidate(_workingCopyStatusProvider(repo));
  return r1 is GitSuccess && r2 is GitSuccess;
}

final AutoDisposeFutureProviderFamily<List<WorkingFileEntry>, RepoLocation>
    _workingCopyStatusProvider =
    FutureProvider.family.autoDispose<List<WorkingFileEntry>, RepoLocation>(
  (ref, repo) async {
    final git = ref.watch(gitReadOperationsProvider);
    final status = await git.getStatus(repo);
    return status.entries;
  },
);

/// Currently selected file path in the working copy panel.
/// `null` means no preview is shown.
final AutoDisposeStateProvider<({String path, bool staged})?>
    _selectedFileProvider =
    StateProvider.autoDispose<({String path, bool staged})?>((_) => null);

/// Working-tree-vs-index diff, keyed by (repo, filePath).
final AutoDisposeFutureProviderFamily<FileDiff?, (RepoLocation, String)>
    _unstagedFileDiffProvider = FutureProvider.family
    .autoDispose<FileDiff?, (RepoLocation, String)>((ref, args) async {
  final (repo, filePath) = args;
  final git = ref.read(gitReadOperationsProvider);
  final result = await git.getDiff(repo, const DiffSpecWorkingTreeVsIndex());
  try {
    return result.files.firstWhere((f) => f.path == filePath);
  } on Object catch (_) {
    return null;
  }
});

/// Index-vs-HEAD diff, keyed by (repo, filePath).
final AutoDisposeFutureProviderFamily<FileDiff?, (RepoLocation, String)>
    _stagedFileDiffProvider = FutureProvider.family
    .autoDispose<FileDiff?, (RepoLocation, String)>((ref, args) async {
  final (repo, filePath) = args;
  final git = ref.read(gitReadOperationsProvider);
  final result = await git.getDiff(repo, const DiffSpecIndexVsHead());
  try {
    return result.files.firstWhere((f) => f.path == filePath);
  } on Object catch (_) {
    return null;
  }
});

bool _canExpandHunks(WorkingFileEntry entry) {
  return entry.workingTreeState != WorkingFileState.untracked &&
      entry.workingTreeState != WorkingFileState.ignored;
}

/// Builds a minimal unified-diff patch containing only the supplied hunks.
String buildPatchForHunks(String filePath, List<DiffHunk> hunks) {
  final buf = StringBuffer()
    ..writeln('diff --git a/$filePath b/$filePath')
    ..writeln('--- a/$filePath')
    ..writeln('+++ b/$filePath');
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
  const WorkingCopyPanel({required this.repo, super.key});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_workingCopyStatusProvider(repo));
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: palette.bg1,
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: TextStyle(color: palette.accentErr)),
        ),
        data: (entries) {
          final unstaged = entries.where((e) =>
              e.workingTreeState != WorkingFileState.unmodified).toList();
          final staged = entries.where((e) =>
              e.indexState != WorkingFileState.unmodified).toList();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 380,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _FileList(
                      repo: repo, unstaged: unstaged, staged: staged,
                    )),
                    Divider(height: 1, color: palette.border),
                    CommitCompose(repo: repo),
                  ],
                ),
              ),
              VerticalDivider(width: 1, color: palette.border),
              Expanded(child: _DiffPreviewPane(repo: repo)),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _FileList extends ConsumerWidget {
  const _FileList({
    required this.repo,
    required this.unstaged,
    required this.staged,
  });
  final RepoLocation repo;
  final List<WorkingFileEntry> unstaged;
  final List<WorkingFileEntry> staged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(children: [
      _Header(
        title: 'Unstaged (${unstaged.length})',
        actions: [
          _HeaderAction(
            'Discard all',
            unstaged.isEmpty
                ? null
                : () => _confirmAndDiscardAll(context, ref, repo, unstaged),
            danger: true,
          ),
          _HeaderAction(
            'Stage all',
            unstaged.isEmpty
                ? null
                : () async {
                    await ref
                        .read(gitWriteOperationsProvider)
                        .stageFiles(repo, unstaged.map((e) => e.path).toList());
                    ref.invalidate(_workingCopyStatusProvider(repo));
                  },
          ),
        ],
      ),
      for (final e in unstaged) _FileRow(repo: repo, entry: e, isStaged: false),
      _Header(
        title: 'Staged (${staged.length})',
        actions: [
          _HeaderAction(
            'Unstage all',
            staged.isEmpty
                ? null
                : () async {
                    await ref
                        .read(gitWriteOperationsProvider)
                        .unstageFiles(repo, staged.map((e) => e.path).toList());
                    ref.invalidate(_workingCopyStatusProvider(repo));
                  },
          ),
        ],
      ),
      for (final e in staged) _FileRow(repo: repo, entry: e, isStaged: true),
    ]);
  }
}

Future<void> _confirmAndDiscardAll(
  BuildContext context,
  WidgetRef ref,
  RepoLocation repo,
  List<WorkingFileEntry> entries,
) async {
  final untrackedCount = entries
      .where((e) => e.workingTreeState == WorkingFileState.untracked)
      .length;
  final trackedCount = entries.length - untrackedCount;
  final parts = <String>[];
  if (trackedCount > 0) {
    parts.add('discard local changes to $trackedCount tracked file'
        '${trackedCount == 1 ? '' : 's'}');
  }
  if (untrackedCount > 0) {
    parts.add('delete $untrackedCount untracked file'
        '${untrackedCount == 1 ? '' : 's'}');
  }
  final confirmed = await ConfirmDialog.show(
    context,
    title: 'Discard all unstaged changes',
    body: 'This will ${parts.join(' and ')}. This cannot be undone.',
    confirmLabel: 'Discard all',
    dangerous: true,
  );
  if (!confirmed) return;
  await _discardEntries(ref, repo, entries);
}

// ---------------------------------------------------------------------------

class _HeaderAction {
  const _HeaderAction(this.label, this.onPressed, {this.danger = false});
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.actions = const []});
  final String title;
  final List<_HeaderAction> actions;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: palette.bg2,
      child: Row(children: [
        Text(
          title,
          style: TextStyle(
            color: palette.fg1,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        for (final a in actions)
          TextButton(
            onPressed: a.onPressed,
            style: a.danger
                ? TextButton.styleFrom(foregroundColor: palette.accentErr)
                : null,
            child: Text(a.label),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------

/// A file row. Clicking the row selects the file (shows its diff in the
/// preview pane). The checkbox icon toggles stage/unstage. The chevron
/// expands hunk-level staging.
class _FileRow extends ConsumerStatefulWidget {
  const _FileRow({
    required this.repo,
    required this.entry,
    required this.isStaged,
  });
  final RepoLocation repo;
  final WorkingFileEntry entry;
  final bool isStaged;

  @override
  ConsumerState<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends ConsumerState<_FileRow> {
  bool _expanded = false;
  bool _hover = false;
  final Set<int> _checkedHunks = {};

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      if (!_expanded) _checkedHunks.clear();
    });
  }

  Future<void> _discard() async {
    final entry = widget.entry;
    final isUntracked = entry.workingTreeState == WorkingFileState.untracked;
    final confirmed = await ConfirmDialog.show(
      context,
      title: isUntracked ? 'Delete untracked file' : 'Discard changes',
      body: isUntracked
          ? 'Delete "${entry.path}"? The file is untracked and will be '
              'removed from disk. This cannot be undone.'
          : 'Discard all changes to "${entry.path}"? Local edits will be '
              'lost and the file will be restored to its committed state.',
      confirmLabel: isUntracked ? 'Delete' : 'Discard',
      dangerous: true,
    );
    if (!confirmed) return;
    await _discardEntries(ref, widget.repo, [entry]);
  }

  Future<void> _showContextMenu(Offset globalPos) async {
    final entry = widget.entry;
    final isStaged = widget.isStaged;
    final isUntracked = entry.workingTreeState == WorkingFileState.untracked;
    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: globalPos,
      entries: [
        AppMenuItem(
          value: 'toggle',
          label: isStaged ? 'Unstage' : 'Stage',
          icon: isStaged
              ? Icons.remove_circle_outline
              : Icons.add_circle_outline,
        ),
        if (!isStaged) ...[
          const AppMenuDivider<String>(),
          AppMenuItem(
            value: 'discard',
            label: isUntracked ? 'Delete file' : 'Discard changes',
            icon: Icons.delete_outline,
            danger: true,
          ),
        ],
      ],
    );
    if (selected == null || !mounted) return;
    switch (selected) {
      case 'toggle':
        await _toggleStage();
      case 'discard':
        await _discard();
    }
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

  Future<void> _toggleStage() async {
    final write = ref.read(gitWriteOperationsProvider);
    if (widget.isStaged) {
      await write.unstageFiles(widget.repo, [widget.entry.path]);
    } else {
      await write.stageFiles(widget.repo, [widget.entry.path]);
    }
    ref.invalidate(_workingCopyStatusProvider(widget.repo));
  }

  Future<void> _stageSelectedHunks(List<DiffHunk> allHunks) async {
    final selected = _checkedHunks.toList()..sort();
    final hunksToStage = selected.map((i) => allHunks[i]).toList();
    final patch = buildPatchForHunks(widget.entry.path, hunksToStage);
    final write = ref.read(gitWriteOperationsProvider);
    await write.stagePatch(widget.repo, patch);
    setState(_checkedHunks.clear);
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
    final palette = AppPalette.of(context);
    final sel = ref.watch(_selectedFileProvider);
    final isSelected = sel != null &&
        sel.path == widget.entry.path &&
        sel.staged == widget.isStaged;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
      color: isSelected ? palette.bgAccent : Colors.transparent,
      child: GestureDetector(
        onSecondaryTapDown: (d) => _showContextMenu(d.globalPosition),
        child: InkWell(
        onTap: () {
          ref.read(_selectedFileProvider.notifier).state =
              (path: widget.entry.path, staged: widget.isStaged);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            if (_canExpand)
              GestureDetector(
                onTap: _toggleExpanded,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: isSelected ? Colors.white70 : palette.fg2,
                  ),
                ),
              )
            else
              const SizedBox(width: 18),
            GestureDetector(
              onTap: _toggleStage,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Icon(
                  widget.isStaged
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 14,
                  color: isSelected ? Colors.white : palette.fg1,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _StateBadge(
              state: widget.isStaged
                  ? widget.entry.indexState
                  : widget.entry.workingTreeState,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.entry.path,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isSelected ? Colors.white : palette.fg0,
                    fontSize: 12.5))),
            if (_checkedHunks.isNotEmpty)
              _buildStageSelectedButton(),
            if (!widget.isStaged && _hover && _checkedHunks.isEmpty)
              _DiscardIconButton(
                isSelected: isSelected,
                onPressed: _discard,
              ),
          ]),
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildStageSelectedButton() {
    final diffAsync = ref.watch(
      _unstagedFileDiffProvider((widget.repo, widget.entry.path)),
    );
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
    final diffAsync = ref.watch(
      _unstagedFileDiffProvider((widget.repo, widget.entry.path)),
    );
    return diffAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(left: 32, top: 4, bottom: 4),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(left: 32, top: 2, bottom: 2),
        child: Text(
          'Diff error: $e',
          style: TextStyle(
            color: AppPalette.of(context).accentErr,
            fontSize: 11,
          ),
        ),
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

class _DiscardIconButton extends StatelessWidget {
  const _DiscardIconButton({required this.isSelected, required this.onPressed});
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: 'Discard changes',
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(3),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.delete_outline,
              size: 14,
              color: isSelected ? Colors.white : palette.accentErr,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _HunkRow extends StatelessWidget {
  const _HunkRow({
    required this.hunk,
    required this.index,
    required this.isChecked,
    required this.onToggle,
  });
  final DiffHunk hunk;
  final int index;
  final bool isChecked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onToggle,
      child: Container(
        color: palette.bg0,
        padding: const EdgeInsets.only(left: 32, right: 12, top: 3, bottom: 3),
        child: Row(children: [
          Icon(
            isChecked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 13,
            color: palette.fg2,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hunk.header,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.accentRemote,
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
  const _StateBadge({required this.state});
  final WorkingFileState state;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final (label, color) = _info(state, p);
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
  (String, Color) _info(WorkingFileState s, AppPalette p) {
    switch (s) {
      case WorkingFileState.added: return ('A', p.accentCurrent);
      case WorkingFileState.modified: return ('M', p.accentTag);
      case WorkingFileState.deleted: return ('D', p.accentErr);
      case WorkingFileState.renamed: return ('R', p.accentRemote);
      case WorkingFileState.untracked: return ('?', p.fg2);
      case WorkingFileState.conflicted: return ('U', p.accentWarn);
      case WorkingFileState.ignored: return ('I', p.fg3);
      case WorkingFileState.unmodified: return ('', Colors.transparent);
    }
  }
}

// ---------------------------------------------------------------------------
// Diff preview pane — renders the selected file's diff.
// ---------------------------------------------------------------------------

class _DiffPreviewPane extends ConsumerWidget {
  const _DiffPreviewPane({required this.repo});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final sel = ref.watch(_selectedFileProvider);
    if (sel == null) {
      return Container(
        color: palette.bg1,
        alignment: Alignment.center,
        child: Text(
          'Select a file to preview changes',
          style: TextStyle(
            color: palette.fg3,
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    final provider = sel.staged
        ? _stagedFileDiffProvider((repo, sel.path))
        : _unstagedFileDiffProvider((repo, sel.path));
    final async = ref.watch(provider);
    return ColoredBox(
      color: palette.bg1,
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Diff error: $e',
              style: TextStyle(color: palette.accentErr)),
        ),
        data: (fileDiff) {
          if (fileDiff == null) {
            return Center(
              child: Text(
                'No diff available (untracked or unchanged)',
                style: TextStyle(color: palette.fg3, fontSize: 12),
              ),
            );
          }
          if (fileDiff.isBinary) {
            return Center(
              child: Text(
                'Binary file (no preview)',
                style: TextStyle(
                  color: palette.fg2,
                  fontStyle: FontStyle.italic,
                ),
              ),
            );
          }
          final language = languageForPath(sel.path);
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _DiffHeader(path: sel.path, fileDiff: fileDiff),
              for (final h in fileDiff.hunks)
                _HunkBlock(hunk: h, language: language),
            ],
          );
        },
      ),
    );
  }
}

class _DiffHeader extends StatelessWidget {
  const _DiffHeader({required this.path, required this.fileDiff});
  final String path;
  final FileDiff fileDiff;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.bg3,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(path,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.fg0, fontSize: 12)),
          ),
          Text(
            '+${fileDiff.linesAdded} -${fileDiff.linesDeleted}',
            style: TextStyle(color: palette.fg2, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _HunkBlock extends StatelessWidget {
  const _HunkBlock({required this.hunk, this.language});
  final DiffHunk hunk;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: palette.bg2,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(hunk.header,
                style: TextStyle(
                  color: palette.fg2,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  fontFamily: 'monospace',
                )),
          ),
          for (final line in hunk.lines)
            _DiffLine(line: line, language: language),
        ],
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line, this.language});
  final DiffLine line;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final Color bg;
    final String prefix;
    switch (line.kind) {
      case DiffLineKind.addition:
        bg = palette.accentCurrent.withValues(alpha: 0.10);
        prefix = '+';
      case DiffLineKind.deletion:
        bg = palette.accentErr.withValues(alpha: 0.12);
        prefix = '-';
      case DiffLineKind.context:
        bg = Colors.transparent;
        prefix = ' ';
    }
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(line.oldLine?.toString() ?? '',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: palette.fg3, fontSize: 11, fontFamily: 'monospace')),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: Text(line.newLine?.toString() ?? '',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: palette.fg3, fontSize: 11, fontFamily: 'monospace')),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 12,
            child: Text(prefix,
                style: TextStyle(
                    color: palette.fg3, fontSize: 12, fontFamily: 'monospace')),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: buildHighlightedSpans(
                  line.content,
                  language,
                  baseColor: palette.fg0,
                ),
              ),
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }
}
