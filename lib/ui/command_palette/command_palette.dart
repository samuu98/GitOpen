import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/active_workspace_provider.dart';
import '../../application/main_view_provider.dart';
import '../../application/providers.dart';
import '../../application/repo_revision.dart';
import '../../application/settings/settings_open_provider.dart';
import '../../domain/refs/branch.dart';
import '../../domain/repositories/repo_location.dart';
import '../checkout/safe_checkout.dart';
import '../dialogs/branch_create_dialog.dart';
import '../theme/app_palette.dart';

/// A single palette entry.
class _Command {
  final String label;
  final String? category;
  final IconData icon;
  final Future<void> Function() run;
  const _Command({
    required this.label,
    required this.icon,
    required this.run,
    this.category,
  });
}

/// Fork/VS Code-style command palette. Open with Ctrl+P; type to filter
/// actions and branches, ↑/↓ to move, Enter to run, Esc to dismiss.
class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const CommandPalette(),
    );
  }

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _queryCtl = TextEditingController();
  final _focus = FocusNode();
  int _selected = 0;

  @override
  void dispose() {
    _queryCtl.dispose();
    _focus.dispose();
    super.dispose();
  }

  RepoLocation? get _activeRepo {
    final id = ref.read(activeWorkspaceIdProvider);
    if (id == null) return null;
    final ws = ref
        .read(workspaceManagerProvider)
        .where((w) => w.location.id == id)
        .cast<dynamic>()
        .firstOrNull;
    return ws?.location as RepoLocation?;
  }

  List<_Command> _allCommands() {
    final repo = _activeRepo;
    final commands = <_Command>[];

    if (repo != null) {
      commands.addAll([
        _Command(
          label: 'Fetch',
          category: 'Git',
          icon: Icons.cloud_download_outlined,
          run: () async =>
              ref.read(triggerFetchProvider.notifier).state++,
        ),
        _Command(
          label: 'Commit',
          category: 'Git',
          icon: Icons.check,
          run: () async =>
              ref.read(triggerCommitProvider.notifier).state++,
        ),
        _Command(
          label: 'Refresh',
          category: 'Git',
          icon: Icons.refresh,
          run: () async => refreshRepo(ref, repo),
        ),
        _Command(
          label: 'New branch…',
          category: 'Git',
          icon: Icons.alt_route,
          run: () async {
            await BranchCreateDialog.show(context, repo);
            refreshRepo(ref, repo);
          },
        ),
        _Command(
          label: 'View: Commit graph',
          category: 'View',
          icon: Icons.account_tree_outlined,
          run: () async =>
              ref.read(mainViewProvider.notifier).state = MainView.graph,
        ),
        _Command(
          label: 'View: Working changes',
          category: 'View',
          icon: Icons.edit_note,
          run: () async =>
              ref.read(mainViewProvider.notifier).state = MainView.changes,
        ),
      ]);

      // Branch checkout entries from the cached branch list (locals only).
      final branches =
          ref.read(branchesProvider(repo)).valueOrNull ?? const <Branch>[];
      for (final b in branches.where((b) => !b.isRemote && !b.isCurrent)) {
        commands.add(_Command(
          label: 'Checkout ${b.name}',
          category: 'Branch',
          icon: Icons.swap_horiz,
          run: () async {
            await safeCheckout(
              context: context,
              ref: ref,
              repo: repo,
              targetRef: b.name,
            );
          },
        ));
      }
    }

    commands.add(_Command(
      label: 'Open settings',
      category: 'App',
      icon: Icons.settings,
      run: () async => ref.read(settingsOpenProvider.notifier).state = true,
    ));
    return commands;
  }

  List<_Command> _filtered(List<_Command> all) {
    final q = _queryCtl.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((c) => '${c.category} ${c.label}'.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _execute(_Command c) async {
    Navigator.of(context).pop();
    await c.run();
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta).clamp(0, count - 1));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final filtered = _filtered(_allCommands());
    if (_selected >= filtered.length) {
      _selected = filtered.isEmpty ? 0 : filtered.length - 1;
    }

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 90),
      backgroundColor: palette.bg2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 560,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            switch (event.logicalKey) {
              case LogicalKeyboardKey.arrowDown:
                _move(1, filtered.length);
                return KeyEventResult.handled;
              case LogicalKeyboardKey.arrowUp:
                _move(-1, filtered.length);
                return KeyEventResult.handled;
              case LogicalKeyboardKey.enter:
              case LogicalKeyboardKey.numpadEnter:
                if (filtered.isNotEmpty) _execute(filtered[_selected]);
                return KeyEventResult.handled;
              case LogicalKeyboardKey.escape:
                Navigator.of(context).pop();
                return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextField(
                  controller: _queryCtl,
                  focusNode: _focus,
                  autofocus: true,
                  onChanged: (_) => setState(() => _selected = 0),
                  style: TextStyle(color: palette.fg0, fontSize: 14),
                  decoration: InputDecoration(
                    prefixIcon:
                        Icon(Icons.search, size: 18, color: palette.fg2),
                    hintText: 'Type a command or branch…',
                    hintStyle: TextStyle(color: palette.fg3),
                    border: InputBorder.none,
                  ),
                ),
              ),
              Divider(height: 1, color: palette.border),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No matching commands',
                            style: TextStyle(color: palette.fg2)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          final isSel = i == _selected;
                          return InkWell(
                            onTap: () => _execute(c),
                            child: Container(
                              color: isSel
                                  ? palette.bgAccent
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 9),
                              child: Row(
                                children: [
                                  Icon(c.icon,
                                      size: 15,
                                      color: isSel
                                          ? Colors.white
                                          : palette.fg2),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(c.label,
                                        style: TextStyle(
                                            color: isSel
                                                ? Colors.white
                                                : palette.fg0,
                                            fontSize: 13)),
                                  ),
                                  if (c.category != null)
                                    Text(c.category!,
                                        style: TextStyle(
                                            color: isSel
                                                ? Colors.white70
                                                : palette.fg3,
                                            fontSize: 11)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
