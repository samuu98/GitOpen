import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/bottom_panel/diff_syntax.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/toolbar/toolbar_buttons.dart';
import 'package:gitopen/ui/toolbar/toolbar_prompt.dart';
import 'package:gitopen/ui/working_copy/diff_preview_pane.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

/// Toolbar dropdown with the stash actions: save, apply, pop, list.
class StashDropdown extends ConsumerStatefulWidget {
  const StashDropdown({required this.enabled, required this.repo, super.key});
  final bool enabled;
  final RepoLocation? repo;

  @override
  ConsumerState<StashDropdown> createState() => _StashDropdownState();
}

class _StashDropdownState extends ConsumerState<StashDropdown> {
  final _menuController = MenuController();

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menuController,
      style: appMenuStyle(context),
      menuChildren: widget.enabled && widget.repo != null
          ? _buildStashMenuItems(widget.repo!)
          : const [],
      child: ToolbarDropdownButton(
        icon: Icons.inventory_2_outlined,
        label: 'Stash',
        enabled: widget.enabled,
        onTap: () => _menuController.isOpen
            ? _menuController.close()
            : _menuController.open(),
      ),
    );
  }

  List<Widget> _buildStashMenuItems(RepoLocation repo) {
    final selected = ref.watch(selectedFileProvider);
    final status = ref.watch(workingCopyStatusProvider(repo)).value;
    final selectedEntry = selected == null
        ? null
        : _entryForSelection(status ?? const [], selected.path);
    return [
      AppMenuButton(
        icon: Icons.save_outlined,
        label: 'Stash changes…',
        onPressed: () async {
          _menuController.close();
          if (!context.mounted) return;
          await _stashSave(repo);
        },
      ),
      if (selected != null)
        AppMenuButton(
          icon: Icons.inventory_outlined,
          label: 'Stash selected file…',
          onPressed: () async {
            _menuController.close();
            if (!context.mounted) return;
            await _stashSelectedFile(
              repo,
              selected.path,
              includeUntracked:
                  selectedEntry?.workingTreeState == WorkingFileState.untracked,
            );
          },
        ),
      AppMenuButton(
        icon: Icons.arrow_downward,
        label: 'Apply latest',
        onPressed: () async {
          _menuController.close();
          await ref
              .read(gitActionsControllerProvider)
              .stashApply(
                context,
                repo,
                0,
              );
        },
      ),
      AppMenuButton(
        icon: Icons.eject_outlined,
        label: 'Pop latest',
        onPressed: () async {
          _menuController.close();
          await ref
              .read(gitActionsControllerProvider)
              .stashPop(
                context,
                repo,
                0,
              );
        },
      ),
      const AppMenuAnchorDivider(),
      AppMenuButton(
        icon: Icons.list_outlined,
        label: 'View stashes…',
        onPressed: () async {
          _menuController.close();
          if (!context.mounted) return;
          await _viewStashes(repo);
        },
      ),
    ];
  }

  Future<void> _stashSave(RepoLocation repo) async {
    final msg = await appPromptText(
      context,
      'Stash changes',
      label: 'Message (optional)',
    );
    if (!mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .stashSave(context, repo, msg?.trim() ?? '');
  }

  Future<void> _stashSelectedFile(
    RepoLocation repo,
    String path, {
    required bool includeUntracked,
  }) async {
    final msg = await appPromptText(
      context,
      'Stash selected file',
      label: 'Message (optional)',
    );
    if (!mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .stashSave(
          context,
          repo,
          msg?.trim() ?? '',
          includeUntracked: includeUntracked,
          paths: [path],
        );
    ref
      ..invalidate(workingCopyStatusProvider(repo))
      ..invalidate(unstagedFileDiffProvider((repo, path)))
      ..invalidate(stagedFileDiffProvider((repo, path)));
  }

  Future<void> _viewStashes(RepoLocation repo) async {
    final stashes = await ref.read(gitReadOperationsProvider).getStashes(repo);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _StashListDialog(repo: repo, initialStashes: stashes),
    );
  }

  WorkingFileEntry? _entryForSelection(
    List<WorkingFileEntry> entries,
    String path,
  ) {
    for (final entry in entries) {
      if (entry.path == path) return entry;
    }
    return null;
  }
}

final _stashDiffProvider = FutureProvider.family
    .autoDispose<DiffResult, ({RepoLocation repo, int index})>(
      (ref, key) => ref
          .watch(gitReadOperationsProvider)
          .getStashDiff(key.repo, key.index),
    );

class _StashListDialog extends ConsumerStatefulWidget {
  const _StashListDialog({
    required this.repo,
    required this.initialStashes,
  });

  final RepoLocation repo;
  final List<Stash> initialStashes;

  @override
  ConsumerState<_StashListDialog> createState() => _StashListDialogState();
}

class _StashListDialogState extends ConsumerState<_StashListDialog> {
  late List<Stash> _stashes = List.of(widget.initialStashes);
  int _selected = 0;

  Stash? get _selectedStash {
    if (_stashes.isEmpty) return null;
    final index = _selected.clamp(0, _stashes.length - 1);
    return _stashes[index];
  }

  Future<void> _refreshStashes() async {
    final stashes = await ref
        .read(gitReadOperationsProvider)
        .getStashes(widget.repo);
    if (!mounted) return;
    setState(() {
      _stashes = stashes;
      if (_stashes.isEmpty) {
        _selected = 0;
      } else if (_selected >= _stashes.length) {
        _selected = _stashes.length - 1;
      }
    });
  }

  Future<void> _apply() async {
    final stash = _selectedStash;
    if (stash == null) return;
    await ref
        .read(gitActionsControllerProvider)
        .stashApply(context, widget.repo, stash.index);
  }

  Future<void> _pop() async {
    final stash = _selectedStash;
    if (stash == null) return;
    await ref
        .read(gitActionsControllerProvider)
        .stashPop(context, widget.repo, stash.index);
    await _refreshStashes();
  }

  Future<void> _drop() async {
    final stash = _selectedStash;
    if (stash == null) return;
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Drop stash',
      body: 'Drop "stash@{${stash.index}}"? This cannot be undone.',
      confirmLabel: 'Drop',
      dangerous: true,
    );
    if (!confirmed || !mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .stashDrop(context, widget.repo, stash.index);
    await _refreshStashes();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final stash = _selectedStash;
    return AppDialog(
      title: 'Stashes',
      width: 820,
      contentPadding: const EdgeInsets.all(12),
      content: _stashes.isEmpty
          ? SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'No stashes.',
                  style: TextStyle(color: palette.fg2, fontSize: 12.5),
                ),
              ),
            )
          : SizedBox(
              height: 430,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 240,
                    child: _StashList(
                      stashes: _stashes,
                      selected: _selected,
                      onSelected: (i) => setState(() => _selected = i),
                    ),
                  ),
                  VerticalDivider(width: 17, color: palette.border),
                  Expanded(
                    child: stash == null
                        ? const SizedBox.shrink()
                        : _StashDiffPreview(
                            repo: widget.repo,
                            stash: stash,
                          ),
                  ),
                ],
              ),
            ),
      actions: [
        AppButton.secondary(
          label: 'Apply',
          icon: Icons.file_download_outlined,
          onPressed: stash == null ? null : _apply,
        ),
        AppButton.secondary(
          label: 'Pop',
          icon: Icons.eject_outlined,
          onPressed: stash == null ? null : _pop,
        ),
        AppButton.danger(
          label: 'Drop',
          icon: Icons.delete_outline,
          onPressed: stash == null ? null : _drop,
        ),
        AppButton.secondary(
          label: 'Close',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _StashList extends StatelessWidget {
  const _StashList({
    required this.stashes,
    required this.selected,
    required this.onSelected,
  });

  final List<Stash> stashes;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView.builder(
      itemCount: stashes.length,
      itemBuilder: (context, i) {
        final stash = stashes[i];
        final isSelected = i == selected;
        return Material(
          color: isSelected ? palette.bgAccent : Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'stash@{${stash.index}}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : palette.fg0,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stash.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white70 : palette.fg2,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StashDiffPreview extends ConsumerWidget {
  const _StashDiffPreview({required this.repo, required this.stash});

  final RepoLocation repo;
  final Stash stash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(
      _stashDiffProvider((repo: repo, index: stash.index)),
    );
    return ColoredBox(
      color: palette.bg1,
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Stash diff error: $e',
            style: TextStyle(color: palette.accentErr, fontSize: 12),
          ),
        ),
        data: (diff) {
          if (diff.files.isEmpty) {
            return Center(
              child: Text(
                'No patch in this stash.',
                style: TextStyle(color: palette.fg3, fontSize: 12),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final file in diff.files) ...[
                DiffHeader(path: file.path, fileDiff: file),
                if (file.isBinary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Binary file',
                      style: TextStyle(color: palette.fg2, fontSize: 12),
                    ),
                  )
                else
                  for (final hunk in file.hunks)
                    HunkBlock(
                      hunk: hunk,
                      language: languageForPath(file.path),
                    ),
              ],
            ],
          );
        },
      ),
    );
  }
}
