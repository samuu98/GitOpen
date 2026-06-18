import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/remote_web_url.dart';
import 'package:gitopen/application/main_view_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/settings_open_provider.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/checkout/safe_checkout.dart';
import 'package:gitopen/ui/dialogs/branch_create_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:url_launcher/url_launcher.dart';

/// A single command-palette entry. [run] is executed by the caller with a
/// live [BuildContext] and [WidgetRef] AFTER the palette closes — so actions
/// that need a mounted context / ref (checkout, dialogs, the git controller)
/// keep working instead of firing on the dialog's disposed element.
class PaletteCommand {
  const PaletteCommand({
    required this.label,
    required this.icon,
    required this.run,
    this.category,
  });
  final String label;
  final String? category;
  final IconData icon;
  final Future<void> Function(BuildContext ctx, WidgetRef ref) run;
}

/// Fork/VS Code-style command palette. Open with the configured shortcut
/// (Ctrl+P by default); type to filter actions and branches, ↑/↓ to move,
/// Enter to run, Esc to dismiss. [show] returns the chosen command (or null);
/// the caller runs it so the action has a live context/ref.
class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key});

  static Future<PaletteCommand?> show(BuildContext context) {
    return showDialog<PaletteCommand>(
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
    return ref
        .read(workspaceManagerProvider)
        .firstWhereOrNull((w) => w.location.id == id)
        ?.location;
  }

  List<PaletteCommand> _allCommands() {
    final repo = _activeRepo;
    final commands = <PaletteCommand>[];

    if (repo != null) {
      commands.addAll([
        PaletteCommand(
          label: 'Fetch',
          category: 'Git',
          icon: Icons.cloud_download_outlined,
          run: (ctx, ref) =>
              ref.read(gitActionsControllerProvider).fetch(ctx, repo),
        ),
        PaletteCommand(
          label: 'Pull',
          category: 'Git',
          icon: Icons.south,
          run: (ctx, ref) =>
              ref.read(gitActionsControllerProvider).pull(ctx, repo),
        ),
        PaletteCommand(
          label: 'Push',
          category: 'Git',
          icon: Icons.north,
          run: (ctx, ref) =>
              ref.read(gitActionsControllerProvider).push(ctx, repo),
        ),
        PaletteCommand(
          label: 'Commit',
          category: 'Git',
          icon: Icons.check,
          run: (ctx, ref) async =>
              ref.read(triggerCommitProvider.notifier).state++,
        ),
        PaletteCommand(
          label: 'New branch…',
          category: 'Git',
          icon: Icons.alt_route,
          run: (ctx, ref) async {
            await BranchCreateDialog.show(ctx, repo);
          },
        ),
        PaletteCommand(
          label: 'Refresh',
          category: 'Git',
          icon: Icons.refresh,
          run: (ctx, ref) async => ref.invalidate(gitReadOperationsProvider),
        ),
        PaletteCommand(
          label: 'Open repository on remote',
          category: 'Git',
          icon: Icons.open_in_browser,
          run: (ctx, ref) async {
            final remotes =
                await ref.read(gitReadOperationsProvider).getRemotes(repo);
            final remote =
                remotes.firstWhereOrNull((r) => r.name == 'origin') ??
                    remotes.firstOrNull;
            final web = remote == null ? null : remoteWebUrl(remote.url);
            if (web != null) {
              await launchUrl(
                Uri.parse(web),
                mode: LaunchMode.externalApplication,
              );
            }
          },
        ),
        PaletteCommand(
          label: 'View: Commit graph',
          category: 'View',
          icon: Icons.account_tree_outlined,
          run: (ctx, ref) async =>
              ref.read(mainViewProvider.notifier).state = MainView.graph,
        ),
        PaletteCommand(
          label: 'View: Working changes',
          category: 'View',
          icon: Icons.edit_note,
          run: (ctx, ref) async =>
              ref.read(mainViewProvider.notifier).state = MainView.changes,
        ),
        PaletteCommand(
          label: 'View: GitHub',
          category: 'View',
          icon: Icons.cloud_outlined,
          run: (ctx, ref) async =>
              ref.read(mainViewProvider.notifier).state = MainView.github,
        ),
        PaletteCommand(
          label: 'View: Git LFS',
          category: 'View',
          icon: Icons.storage_outlined,
          run: (ctx, ref) async =>
              ref.read(mainViewProvider.notifier).state = MainView.lfs,
        ),
      ]);

      // Checkout entries for the cached local branches (skip the current one).
      final branches =
          ref.read(branchesProvider(repo)).valueOrNull ?? const <Branch>[];
      for (final b in branches.where((b) => !b.isRemote && !b.isCurrent)) {
        commands.add(
          PaletteCommand(
            label: 'Checkout ${b.name}',
            category: 'Branch',
            icon: Icons.swap_horiz,
            run: (ctx, ref) async {
              await safeCheckout(
                context: ctx,
                ref: ref,
                repo: repo,
                targetRef: b.name,
              );
            },
          ),
        );
      }
    }

    commands.add(
      PaletteCommand(
        label: 'Open settings',
        category: 'App',
        icon: Icons.settings,
        run: (ctx, ref) async =>
            ref.read(settingsOpenProvider.notifier).state = true,
      ),
    );
    return commands;
  }

  List<PaletteCommand> _filtered(List<PaletteCommand> all) {
    final q = _queryCtl.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((c) => '${c.category} ${c.label}'.toLowerCase().contains(q))
        .toList();
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta).clamp(0, count - 1));
  }

  void _pick(PaletteCommand c) => Navigator.of(context).pop(c);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final radii = AppRadii.of(context);
    final typography = AppTypography.of(context);
    final filtered = _filtered(_allCommands());
    if (_selected >= filtered.length) {
      _selected = filtered.isEmpty ? 0 : filtered.length - 1;
    }

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 90, left: 20, right: 20),
      backgroundColor: palette.bg2,
      shape: RoundedRectangleBorder(
        borderRadius: radii.dialogRadius,
        side: BorderSide(color: palette.border),
      ),
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
                if (filtered.isNotEmpty) _pick(filtered[_selected]);
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
                  style: typography.body.copyWith(color: palette.fg0),
                  decoration: InputDecoration(
                    prefixIcon:
                        Icon(Icons.search, size: 18, color: palette.fg2),
                    hintText: 'Type a command or branch…',
                    hintStyle: typography.body.copyWith(color: palette.fg3),
                    border: InputBorder.none,
                  ),
                ),
              ),
              Divider(height: 1, color: palette.border),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No matching commands',
                          style: typography.body.copyWith(color: palette.fg2),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          final isSel = i == _selected;
                          final fg = isSel ? palette.fg0 : palette.fg1;
                          final catFg = isSel ? palette.fg0 : palette.fg3;
                          return InkWell(
                            onTap: () => _pick(c),
                            child: Container(
                              color:
                                  isSel ? palette.bgAccent : Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    c.icon,
                                    size: 15,
                                    color: isSel ? palette.fg0 : palette.fg2,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      c.label,
                                      style:
                                          typography.body.copyWith(color: fg),
                                    ),
                                  ),
                                  if (c.category != null)
                                    Text(
                                      c.category!,
                                      style: typography.caption
                                          .copyWith(color: catFg),
                                    ),
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
