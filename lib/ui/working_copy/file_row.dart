import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/diff/build_patch_for_hunks.dart';
import 'package:gitopen/application/diff/build_patch_for_lines.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/toolbar/toolbar_prompt.dart';
import 'package:gitopen/ui/working_copy/discard_changes.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

bool _canExpandHunks(WorkingFileEntry entry) {
  return entry.workingTreeState != WorkingFileState.untracked &&
      entry.workingTreeState != WorkingFileState.ignored;
}

String _workingStateLabel(WorkingFileState state) {
  return switch (state) {
    WorkingFileState.added => 'added',
    WorkingFileState.modified => 'modified',
    WorkingFileState.deleted => 'deleted',
    WorkingFileState.renamed => 'renamed',
    WorkingFileState.untracked => 'untracked',
    WorkingFileState.conflicted => 'conflicted',
    WorkingFileState.ignored => 'ignored',
    WorkingFileState.unmodified => 'unmodified',
  };
}

// ---------------------------------------------------------------------------

/// A file row. Clicking the row selects the file (shows its diff in the
/// preview pane). The checkbox icon toggles stage/unstage. The chevron
/// expands hunk-level staging.
class FileRow extends ConsumerStatefulWidget {
  const FileRow({
    required this.repo,
    required this.entry,
    required this.isStaged,
    this.displayName,
    this.indent = 0,
    super.key,
  });
  final RepoLocation repo;
  final WorkingFileEntry entry;
  final bool isStaged;

  /// Text shown for the file (tree mode shows the leaf name); defaults to
  /// the full path. Semantics keep the full path either way.
  final String? displayName;

  /// Extra left padding for tree indentation.
  final double indent;

  @override
  ConsumerState<FileRow> createState() => _FileRowState();
}

class _FileRowState extends ConsumerState<FileRow> {
  bool _expanded = false;
  bool _hover = false;
  final Set<int> _checkedHunks = {};
  final Map<int, Set<int>> _checkedLines = {};

  bool get _hasCheckedLines =>
      _checkedLines.values.any((selected) => selected.isNotEmpty);

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      if (!_expanded) {
        _checkedHunks.clear();
        _checkedLines.clear();
      }
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
    await discardEntries(ref, widget.repo, [entry]);
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
        const AppMenuDivider<String>(),
        const AppMenuItem(
          value: 'stash_file',
          label: 'Stash file…',
          icon: Icons.inventory_outlined,
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
      case 'stash_file':
        await _stashFile();
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
      _checkedLines.remove(index);
    });
  }

  void _toggleLine(int hunkIndex, int lineIndex) {
    setState(() {
      _checkedHunks.remove(hunkIndex);
      final selected = _checkedLines.putIfAbsent(hunkIndex, () => <int>{});
      if (!selected.add(lineIndex)) {
        selected.remove(lineIndex);
      }
      if (selected.isEmpty) _checkedLines.remove(hunkIndex);
    });
  }

  Future<void> _toggleStage() async {
    final write = ref.read(gitWriteOperationsProvider);
    if (widget.isStaged) {
      await write.unstageFiles(widget.repo, [widget.entry.path]);
    } else {
      await write.stageFiles(widget.repo, [widget.entry.path]);
    }
    ref.invalidate(workingCopyStatusProvider(widget.repo));
  }

  Future<void> _stashFile() async {
    final msg = await appPromptText(
      context,
      'Stash file',
      label: 'Message (optional)',
    );
    if (!mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .stashSave(
          context,
          widget.repo,
          msg?.trim() ?? '',
          includeUntracked:
              widget.entry.workingTreeState == WorkingFileState.untracked,
          paths: [widget.entry.path],
        );
    ref
      ..invalidate(workingCopyStatusProvider(widget.repo))
      ..invalidate(unstagedFileDiffProvider((widget.repo, widget.entry.path)))
      ..invalidate(stagedFileDiffProvider((widget.repo, widget.entry.path)));
  }

  Future<void> _stageSelectedHunks(List<DiffHunk> allHunks) async {
    final selected = _checkedHunks.toList()..sort();
    final hunksToStage = selected.map((i) => allHunks[i]).toList();
    final patch = buildPatchForHunks(widget.entry.path, hunksToStage);
    final write = ref.read(gitWriteOperationsProvider);
    await write.stagePatch(widget.repo, patch);
    setState(_checkedHunks.clear);
    ref
      ..invalidate(workingCopyStatusProvider(widget.repo))
      ..invalidate(unstagedFileDiffProvider((widget.repo, widget.entry.path)));
  }

  Future<void> _stageSelectedLines(List<DiffHunk> allHunks) async {
    final patches = <String>[];
    for (final entry in _checkedLines.entries) {
      if (entry.value.isEmpty) continue;
      final patch = buildPatchForLines(
        widget.entry.path,
        allHunks[entry.key],
        entry.value,
      );
      if (patch.isNotEmpty) patches.add(patch);
    }
    if (patches.isEmpty) return;

    final write = ref.read(gitWriteOperationsProvider);
    for (final patch in patches) {
      await write.stagePatch(widget.repo, patch);
    }
    setState(_checkedLines.clear);
    ref
      ..invalidate(workingCopyStatusProvider(widget.repo))
      ..invalidate(unstagedFileDiffProvider((widget.repo, widget.entry.path)));
  }

  Future<void> _discardHunk(DiffHunk hunk, int index) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Discard hunk',
      body:
          'Discard this hunk from "${widget.entry.path}"? Local edits in '
          'the hunk will be lost.',
      confirmLabel: 'Discard hunk',
      dangerous: true,
    );
    if (!confirmed || !mounted) return;
    final patch = buildPatchForHunks(widget.entry.path, [hunk]);
    await ref
        .read(gitActionsControllerProvider)
        .discardHunk(context, widget.repo, patch);
    if (!mounted) return;
    setState(() {
      _checkedHunks.remove(index);
      _checkedLines.remove(index);
    });
    ref
      ..invalidate(workingCopyStatusProvider(widget.repo))
      ..invalidate(unstagedFileDiffProvider((widget.repo, widget.entry.path)));
  }

  bool get _canExpand => !widget.isStaged && _canExpandHunks(widget.entry);

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
    final sel = ref.watch(selectedFileProvider);
    final isSelected =
        sel != null &&
        sel.path == widget.entry.path &&
        sel.staged == widget.isStaged;
    final state = widget.isStaged
        ? widget.entry.indexState
        : widget.entry.workingTreeState;
    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${widget.isStaged ? 'Staged' : 'Unstaged'} '
          '${_workingStateLabel(state)} file ${widget.entry.path}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: isSelected ? palette.bgAccent : Colors.transparent,
          child: GestureDetector(
            onSecondaryTapDown: (d) => _showContextMenu(d.globalPosition),
            child: InkWell(
              onTap: () {
                ref.read(selectedFileProvider.notifier).state = (
                  path: widget.entry.path,
                  staged: widget.isStaged,
                );
              },
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12 + widget.indent,
                  right: 12,
                  top: 4,
                  bottom: 4,
                ),
                child: Row(
                  children: [
                    if (_canExpand)
                      GestureDetector(
                        onTap: _toggleExpanded,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Semantics(
                            button: true,
                            label: _expanded
                                ? 'Collapse hunks'
                                : 'Expand hunks',
                            child: Icon(
                              _expanded
                                  ? Icons.expand_more
                                  : Icons.chevron_right,
                              size: 14,
                              color: isSelected ? Colors.white70 : palette.fg2,
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 18),
                    GestureDetector(
                      onTap: _toggleStage,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Semantics(
                          button: true,
                          label: widget.isStaged
                              ? 'Unstage file'
                              : 'Stage file',
                          child: Icon(
                            widget.isStaged
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 14,
                            color: isSelected ? Colors.white : palette.fg1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    StateBadge(
                      state: widget.isStaged
                          ? widget.entry.indexState
                          : widget.entry.workingTreeState,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.displayName ?? widget.entry.path,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Colors.white : palette.fg0,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (_checkedHunks.isNotEmpty || _hasCheckedLines)
                      _buildStageSelectedButton(),
                    if (!widget.isStaged &&
                        _hover &&
                        _checkedHunks.isEmpty &&
                        !_hasCheckedLines)
                      DiscardIconButton(
                        isSelected: isSelected,
                        onPressed: _discard,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStageSelectedButton() {
    final diffAsync = ref.watch(
      unstagedFileDiffProvider((widget.repo, widget.entry.path)),
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
            onPressed: _hasCheckedLines
                ? () => _stageSelectedLines(fileDiff.hunks)
                : () => _stageSelectedHunks(fileDiff.hunks),
            child: Text(
              _hasCheckedLines
                  ? 'Stage selected lines'
                  : 'Stage selected hunks',
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _buildHunkSection() {
    final diffAsync = ref.watch(
      unstagedFileDiffProvider((widget.repo, widget.entry.path)),
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
              HunkRow(
                hunk: fileDiff.hunks[i],
                index: i,
                isChecked: _checkedHunks.contains(i),
                onToggle: () => _toggleHunk(i),
                selectedLines: _checkedLines[i] ?? const <int>{},
                onToggleLine: (lineIndex) => _toggleLine(i, lineIndex),
                onDiscard: () => _discardHunk(fileDiff.hunks[i], i),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class DiscardIconButton extends StatelessWidget {
  const DiscardIconButton({
    required this.isSelected,
    required this.onPressed,
    super.key,
  });
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

class HunkRow extends StatelessWidget {
  const HunkRow({
    required this.hunk,
    required this.index,
    required this.isChecked,
    required this.onToggle,
    required this.selectedLines,
    required this.onToggleLine,
    required this.onDiscard,
    super.key,
  });
  final DiffHunk hunk;
  final int index;
  final bool isChecked;
  final VoidCallback onToggle;
  final Set<int> selectedLines;
  final ValueChanged<int> onToggleLine;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: palette.bg0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            selected: isChecked,
            label:
                '${isChecked ? 'Selected' : 'Unselected'} '
                'hunk ${index + 1}, ${hunk.header}',
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 32,
                  right: 8,
                  top: 3,
                  bottom: 3,
                ),
                child: Row(
                  children: [
                    Icon(
                      isChecked
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
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
                    Tooltip(
                      message: 'Discard hunk',
                      waitDuration: const Duration(milliseconds: 400),
                      child: Semantics(
                        button: true,
                        label: 'Discard hunk ${index + 1}',
                        child: InkWell(
                          onTap: onDiscard,
                          borderRadius: BorderRadius.circular(3),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.undo,
                              size: 13,
                              color: palette.accentErr,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (final (lineIndex, line) in hunk.lines.indexed)
            _HunkLineRow(
              line: line,
              isChecked: selectedLines.contains(lineIndex),
              onToggle: () => onToggleLine(lineIndex),
            ),
        ],
      ),
    );
  }
}

class _HunkLineRow extends StatelessWidget {
  const _HunkLineRow({
    required this.line,
    required this.isChecked,
    required this.onToggle,
  });
  final DiffLine line;
  final bool isChecked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final selectable = line.kind != DiffLineKind.context;
    final (prefix, bg) = switch (line.kind) {
      DiffLineKind.addition => (
        '+',
        palette.accentCurrent.withValues(alpha: 0.08),
      ),
      DiffLineKind.deletion => ('-', palette.accentErr.withValues(alpha: 0.10)),
      DiffLineKind.context => (' ', Colors.transparent),
    };
    final changeLabel = line.kind == DiffLineKind.addition
        ? 'addition'
        : 'deletion';
    return InkWell(
      onTap: selectable ? onToggle : null,
      child: Semantics(
        button: selectable,
        selected: selectable ? isChecked : null,
        label: selectable
            ? '${isChecked ? 'Selected' : 'Unselected'} $changeLabel '
                  'line ${line.content}'
            : 'Context line ${line.content}',
        child: Container(
          color: bg,
          padding: const EdgeInsets.only(
            left: 50,
            right: 12,
            top: 1,
            bottom: 1,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: selectable
                    ? Icon(
                        isChecked
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 12,
                        color: palette.fg2,
                      )
                    : null,
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 12,
                child: Text(
                  prefix,
                  style: TextStyle(
                    color: palette.fg3,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  line.content,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.fg1,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class StateBadge extends StatelessWidget {
  const StateBadge({required this.state, super.key});
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
      case WorkingFileState.added:
        return ('A', p.accentCurrent);
      case WorkingFileState.modified:
        return ('M', p.accentTag);
      case WorkingFileState.deleted:
        return ('D', p.accentErr);
      case WorkingFileState.renamed:
        return ('R', p.accentRemote);
      case WorkingFileState.untracked:
        return ('?', p.fg2);
      case WorkingFileState.conflicted:
        return ('U', p.accentWarn);
      case WorkingFileState.ignored:
        return ('I', p.fg3);
      case WorkingFileState.unmodified:
        return ('', Colors.transparent);
    }
  }
}
