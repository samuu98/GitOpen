import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/toolbar/toolbar_buttons.dart';
import 'package:gitopen/ui/toolbar/toolbar_prompt.dart';

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
      AppMenuButton(
        icon: Icons.arrow_downward,
        label: 'Apply latest',
        onPressed: () async {
          _menuController.close();
          await ref.read(gitActionsControllerProvider).stashApply(
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
          await ref.read(gitActionsControllerProvider).stashPop(
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
    final msg = await appPromptText(context, 'Stash changes',
        label: 'Message (optional)');
    if (!mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .stashSave(context, repo, msg?.trim() ?? '');
  }

  Future<void> _viewStashes(RepoLocation repo) async {
    final stashes = await ref.read(gitReadOperationsProvider).getStashes(repo);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AppDialog(
          title: 'Stashes',
          width: 420,
          content: stashes.isEmpty
              ? Text('No stashes.',
                  style: TextStyle(color: palette.fg2, fontSize: 12.5))
              : SizedBox(
                  height: 280,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: stashes.length,
                    itemBuilder: (_, i) {
                      final s = stashes[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'stash@{${s.index}}',
                              style: TextStyle(
                                color: palette.fg0,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              s.message,
                              style: TextStyle(
                                  color: palette.fg2, fontSize: 11.5),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            AppButton.secondary(
              label: 'Close',
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        );
      },
    );
  }
}
