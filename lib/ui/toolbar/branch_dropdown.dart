import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/branch_create_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/toolbar/branch_picker_dialog.dart';
import 'package:gitopen/ui/toolbar/toolbar_buttons.dart';
import 'package:gitopen/ui/toolbar/toolbar_prompt.dart';

/// Toolbar dropdown with the branch actions: create, switch, rename, delete.
class BranchDropdown extends ConsumerStatefulWidget {
  const BranchDropdown({required this.enabled, required this.repo, super.key});
  final bool enabled;
  final RepoLocation? repo;

  @override
  ConsumerState<BranchDropdown> createState() => _BranchDropdownState();
}

class _BranchDropdownState extends ConsumerState<BranchDropdown> {
  final _menuController = MenuController();

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menuController,
      style: appMenuStyle(context),
      menuChildren: widget.enabled && widget.repo != null
          ? _buildBranchMenuItems(widget.repo!)
          : const [],
      child: ToolbarDropdownButton(
        icon: Icons.account_tree_outlined,
        label: 'Branch',
        enabled: widget.enabled,
        onTap: () => _menuController.isOpen
            ? _menuController.close()
            : _menuController.open(),
      ),
    );
  }

  List<Widget> _buildBranchMenuItems(RepoLocation repo) {
    return [
      AppMenuButton(
        icon: Icons.add,
        label: 'New branch from HEAD',
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          await BranchCreateDialog.show(context, repo);
        },
      ),
      AppMenuButton(
        icon: Icons.swap_horiz,
        label: 'Switch branch…',
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          await _switchBranch(repo);
        },
      ),
      AppMenuButton(
        icon: Icons.drive_file_rename_outline,
        label: 'Rename current branch…',
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          await _renameBranch(repo);
        },
      ),
      const AppMenuAnchorDivider(),
      AppMenuButton(
        icon: Icons.delete_outline,
        label: 'Delete branch…',
        danger: true,
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          await _deleteBranch(repo);
        },
      ),
    ];
  }

  Future<void> _switchBranch(RepoLocation repo) async {
    final branches =
        await ref.read(gitReadOperationsProvider).getBranches(repo);
    final locals = branches.where((b) => !b.isRemote).toList();
    if (!mounted) return;
    final selected = await _showBranchPickerDialog(
      context,
      title: 'Switch branch',
      branches: locals.map((b) => b.name).toList(),
    );
    if (selected == null || !mounted) return;
    await ref.read(gitActionsControllerProvider).checkout(
          context,
          repo,
          selected,
        );
  }

  Future<void> _renameBranch(RepoLocation repo) async {
    final branches =
        await ref.read(gitReadOperationsProvider).getBranches(repo);
    final current = branches.where((b) => b.isCurrent).firstOrNull;
    if (current == null || !mounted) return;
    final newName = await appPromptText(context, 'Rename current branch',
        label: 'New name', initial: current.name);
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .renameBranch(context, repo, current.name, newName.trim());
  }

  Future<void> _deleteBranch(RepoLocation repo) async {
    final branches =
        await ref.read(gitReadOperationsProvider).getBranches(repo);
    final locals = branches.where((b) => !b.isRemote).toList();
    if (!mounted) return;
    final selected = await _showBranchPickerDialog(
      context,
      title: 'Delete branch',
      branches: locals.map((b) => b.name).toList(),
    );
    if (selected == null || !mounted) return;
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete branch',
      body: 'Delete "$selected"? This cannot be undone.',
      confirmLabel: 'Delete',
      dangerous: true,
    );
    if (!confirmed || !mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .deleteBranch(context, repo, selected, force: true);
  }

  Future<String?> _showBranchPickerDialog(
    BuildContext context, {
    required String title,
    required List<String> branches,
  }) async {
    if (branches.isEmpty) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => BranchPickerDialog(title: title, branches: branches),
    );
  }
}
