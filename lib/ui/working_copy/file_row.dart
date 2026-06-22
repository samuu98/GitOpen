import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/file_row_actions.dart';
import 'package:gitopen/ui/working_copy/hunk_row.dart';
import 'package:gitopen/ui/working_copy/state_badge.dart';
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
  late final FileRowActions _actions = FileRowActions(ref);

  bool get _hasCheckedLines =>
      _checkedLines.values.any((selected) => selected.isNotEmpty);

  /// The current line selection as `(hunk, lines)` pairs for the action calls.
  List<LineSelection> _lineSelections(List<DiffHunk> allHunks) => [
    for (final e in _checkedLines.entries)
      if (e.value.isNotEmpty) (hunk: allHunks[e.key], lines: e.value),
  ];

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      if (!_expanded) {
        _checkedHunks.clear();
        _checkedLines.clear();
      }
    });
  }

  Future<void> _discard() =>
      _actions.discardFile(context, widget.repo, widget.entry);

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

  Future<void> _toggleStage() => _actions.toggleStage(
    widget.repo,
    widget.entry.path,
    isStaged: widget.isStaged,
  );

  Future<void> _stashFile() =>
      _actions.stash(context, widget.repo, widget.entry);

  Future<void> _stageSelectedHunks(List<DiffHunk> allHunks) async {
    final selected = _checkedHunks.toList()..sort();
    final hunksToStage = selected.map((i) => allHunks[i]).toList();
    await _actions.stageHunks(widget.repo, widget.entry.path, hunksToStage);
    setState(_checkedHunks.clear);
  }

  Future<void> _stageSelectedLines(List<DiffHunk> allHunks) async {
    await _actions.stageLines(
      widget.repo,
      widget.entry.path,
      _lineSelections(allHunks),
    );
    setState(_checkedLines.clear);
  }

  Future<void> _discardHunk(DiffHunk hunk, int index) async {
    final ok = await _actions.discardHunk(
      context,
      widget.repo,
      widget.entry.path,
      hunk,
    );
    if (!ok || !mounted) return;
    setState(() {
      _checkedHunks.remove(index);
      _checkedLines.remove(index);
    });
  }

  // --- Unstage (staged rows): non-destructive, no confirm. ---

  Future<void> _unstageSelectedHunks(List<DiffHunk> allHunks) async {
    final selected = _checkedHunks.toList()..sort();
    final hunks = selected.map((i) => allHunks[i]).toList();
    await _actions.unstageHunks(widget.repo, widget.entry.path, hunks);
    setState(_checkedHunks.clear);
  }

  Future<void> _unstageSelectedLines(List<DiffHunk> allHunks) async {
    await _actions.unstageLines(
      widget.repo,
      widget.entry.path,
      _lineSelections(allHunks),
    );
    setState(_checkedLines.clear);
  }

  Future<void> _unstageHunk(DiffHunk hunk, int index) async {
    await _actions.unstageHunk(widget.repo, widget.entry.path, hunk);
    if (!mounted) return;
    setState(() {
      _checkedHunks.remove(index);
      _checkedLines.remove(index);
    });
  }

  // --- Discard selected lines/hunks (unstaged rows): confirm + progress. ---

  Future<void> _discardSelectedHunks(List<DiffHunk> allHunks) async {
    final selected = _checkedHunks.toList()..sort();
    final hunks = selected.map((i) => allHunks[i]).toList();
    final ok = await _actions.discardSelectedHunks(
      context,
      widget.repo,
      widget.entry.path,
      hunks,
    );
    if (ok) setState(_checkedHunks.clear);
  }

  Future<void> _discardSelectedLines(List<DiffHunk> allHunks) async {
    final ok = await _actions.discardSelectedLines(
      context,
      widget.repo,
      widget.entry.path,
      _lineSelections(allHunks),
    );
    if (ok) setState(_checkedLines.clear);
  }

  /// Staged rows expand against the index-vs-HEAD diff (for unstaging);
  /// unstaged rows against the working-tree-vs-index diff (for staging/
  /// discarding). Untracked/ignored unstaged files have no hunks to show.
  bool get _canExpand => widget.isStaged
      ? widget.entry.indexState != WorkingFileState.unmodified
      : _canExpandHunks(widget.entry);

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
                      // Full path on hover — the row ellipsizes long names and
                      // the panel may be too narrow to show them otherwise.
                      child: Tooltip(
                        message: widget.entry.path,
                        waitDuration: const Duration(milliseconds: 500),
                        child: Text(
                          widget.displayName ?? widget.entry.path,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? Colors.white : palette.fg0,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                    if (_checkedHunks.isNotEmpty || _hasCheckedLines)
                      _buildSelectionActions(),
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

  Widget _buildSelectionActions() {
    final diffAsync = ref.watch(
      widget.isStaged
          ? stagedFileDiffProvider((widget.repo, widget.entry.path))
          : unstagedFileDiffProvider((widget.repo, widget.entry.path)),
    );
    return diffAsync.maybeWhen(
      data: (fileDiff) {
        if (fileDiff == null) return const SizedBox.shrink();
        final hunks = fileDiff.hunks;
        final byLines = _hasCheckedLines;
        if (widget.isStaged) {
          return _selectionButton(
            label: byLines
                ? 'Unstage selected lines'
                : 'Unstage selected hunks',
            onPressed: byLines
                ? () => _unstageSelectedLines(hunks)
                : () => _unstageSelectedHunks(hunks),
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _selectionButton(
              label: byLines ? 'Stage selected lines' : 'Stage selected hunks',
              onPressed: byLines
                  ? () => _stageSelectedLines(hunks)
                  : () => _stageSelectedHunks(hunks),
            ),
            _selectionButton(
              label: byLines
                  ? 'Discard selected lines'
                  : 'Discard selected hunks',
              danger: true,
              onPressed: byLines
                  ? () => _discardSelectedLines(hunks)
                  : () => _discardSelectedHunks(hunks),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _selectionButton({
    required String label,
    required VoidCallback onPressed,
    bool danger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 11),
          foregroundColor: danger ? AppPalette.of(context).accentErr : null,
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  Widget _buildHunkSection() {
    final diffAsync = ref.watch(
      widget.isStaged
          ? stagedFileDiffProvider((widget.repo, widget.entry.path))
          : unstagedFileDiffProvider((widget.repo, widget.entry.path)),
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
                staged: widget.isStaged,
                isChecked: _checkedHunks.contains(i),
                onToggle: () => _toggleHunk(i),
                selectedLines: _checkedLines[i] ?? const <int>{},
                onToggleLine: (lineIndex) => _toggleLine(i, lineIndex),
                onAction: () => widget.isStaged
                    ? _unstageHunk(fileDiff.hunks[i], i)
                    : _discardHunk(fileDiff.hunks[i], i),
              ),
          ],
        );
      },
    );
  }
}
