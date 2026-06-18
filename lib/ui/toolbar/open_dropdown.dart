import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/launcher/repo_launcher.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/toolbar/toolbar_buttons.dart';

/// Toolbar dropdown to reveal the repo in the file explorer, a terminal or an
/// installed editor.
class OpenDropdown extends ConsumerStatefulWidget {
  const OpenDropdown({required this.enabled, required this.repo, super.key});
  final bool enabled;
  final RepoLocation? repo;

  @override
  ConsumerState<OpenDropdown> createState() => _OpenDropdownState();
}

class _OpenDropdownState extends ConsumerState<OpenDropdown> {
  final _menuController = MenuController();

  @override
  Widget build(BuildContext context) {
    final editorsAsync = ref.watch(availableEditorsProvider);
    return MenuAnchor(
      controller: _menuController,
      style: appMenuStyle(context),
      menuChildren: widget.enabled && widget.repo != null
          ? _buildMenuItems(widget.repo!, editorsAsync.value ?? const [])
          : const [],
      child: ToolbarDropdownButton(
        icon: Icons.open_in_new,
        label: 'Open',
        enabled: widget.enabled,
        onTap: () => _menuController.isOpen
            ? _menuController.close()
            : _menuController.open(),
      ),
    );
  }

  List<Widget> _buildMenuItems(RepoLocation repo, List<EditorTarget> editors) {
    final items = <Widget>[
      AppMenuButton(
        icon: Icons.folder_open,
        label: 'Show in file explorer',
        onPressed: () {
          _menuController.close();
          unawaited(
            _run(() => ref.read(repoLauncherProvider).revealInFiles(repo)),
          );
        },
      ),
      AppMenuButton(
        icon: Icons.terminal,
        label: 'Open in terminal',
        onPressed: () {
          _menuController.close();
          unawaited(
            _run(() => ref.read(repoLauncherProvider).openInTerminal(repo)),
          );
        },
      ),
      const AppMenuAnchorDivider(),
    ];

    if (editors.isEmpty) {
      items.add(AppMenuButton(
        icon: Icons.code,
        label: 'Open in VS Code',
        onPressed: () {
          _menuController.close();
          unawaited(
            _run(
              () => ref.read(repoLauncherProvider).openInEditor(
                    repo,
                    const EditorTarget(
                      id: 'vscode',
                      displayName: 'VS Code',
                      executable: 'code',
                    ),
                  ),
            ),
          );
        },
      ));
    } else {
      for (final editor in editors) {
        items.add(AppMenuButton(
          icon: Icons.code,
          label: 'Open in ${editor.displayName}',
          onPressed: () {
            _menuController.close();
            unawaited(
              _run(
                () =>
                    ref.read(repoLauncherProvider).openInEditor(repo, editor),
              ),
            );
          },
        ));
      }
    }
    return items;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on LauncherException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }
}
