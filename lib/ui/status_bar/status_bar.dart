import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/workspace.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/account_switcher_dialog.dart';
import 'package:gitopen/ui/operations/activity_panel.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final active = workspaces
        .where((w) => w.location.id == activeId)
        .cast<Workspace?>()
        .firstOrNull;

    if (active == null) {
      return Container(height: 22, color: p.bg3);
    }
    final repo = active.location;
    final branchesAsync = ref.watch(branchesProvider(repo));
    final statusAsync = ref.watch(repoStatusProvider(repo));
    final inProgressAsync = ref.watch(repoStateProvider(repo));
    final ops = ref.watch(operationsProvider);
    final running =
        ops.where((o) => o.status == OperationStatus.running).length;

    return Container(
      height: 22,
      color: p.bg3,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        branchesAsync.when(
          // Keep the branch name during background reloads (auto-refresh on
          // fetch / focus regain) instead of flashing 'loading...'.
          skipLoadingOnReload: true,
          loading: () => Text(
            'loading...',
            style: TextStyle(color: p.fg2, fontSize: 11),
          ),
          // The explicit parameter types document the AsyncValue.when error
          // signature; the closure-parameter-type lint is not useful here.
          // ignore: avoid_types_on_closure_parameters
          error: (Object e, StackTrace s) => const SizedBox.shrink(),
          data: (branches) {
            if (branches.isEmpty) return const SizedBox.shrink();
            final cur = branches.firstWhere(
              (b) => b.isCurrent,
              orElse: () => branches.first,
            );
            return Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.fork_right, size: 11, color: p.accentCurrent),
              const SizedBox(width: 4),
              Text(cur.name, style: TextStyle(color: p.fg0, fontSize: 11)),
              // ahead/behind for the current branch comes from RepoStatus
              // (cheap, single `git status` call), NOT from for-each-ref's
              // `upstream:track` atom which becomes O(N×commits) on repos
              // with many local branches that diverge a lot from upstream.
              if ((statusAsync.valueOrNull?.ahead ?? 0) > 0)
                Text(' ↑${statusAsync.valueOrNull!.ahead}',
                    style: TextStyle(color: p.accentCurrent, fontSize: 11)),
              if ((statusAsync.valueOrNull?.behind ?? 0) > 0)
                Text(' ↓${statusAsync.valueOrNull!.behind}',
                    style: TextStyle(color: p.accentTag, fontSize: 11)),
            ]);
          },
        ),
        const SizedBox(width: 16),
        Expanded(
          child: InkWell(
            onTap: () => Clipboard.setData(ClipboardData(text: repo.path)),
            child: Text(
              repo.path,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.fg2, fontSize: 11),
            ),
          ),
        ),
        if (inProgressAsync.valueOrNull != null &&
            inProgressAsync.valueOrNull != InProgressOp.none) ...[
          Icon(Icons.warning_amber, size: 12, color: p.accentTag),
          const SizedBox(width: 4),
          Text(
            inProgressAsync.valueOrNull!.name,
            style: TextStyle(color: p.accentTag, fontSize: 11),
          ),
          const SizedBox(width: 12),
        ],
        _ActiveAccountChip(repo: repo),
        const SizedBox(width: 12),
        InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const ActivityPanel(),
          ),
          child: Row(children: [
            Icon(Icons.workspaces_outline, size: 11, color: p.fg2),
            const SizedBox(width: 4),
            Text(
              '$running op${running == 1 ? '' : 's'}',
              style: TextStyle(color: p.fg2, fontSize: 11),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Small status-bar chip showing which auth profile is in effect for the
/// active repo.  Clicking it opens the [AccountSwitcherDialog] so the user
/// can rebind the repo without waiting for a push to fail.
///
/// Reads the resolved profile via [repoActiveProfileProvider] (cached) — do
/// NOT call `AuthResolver.resolveForRepo` inline in `build`; doing so
/// recreates the future on each rebuild, and FutureBuilder's completion
/// triggers another rebuild → another future, ad infinitum.
class _ActiveAccountChip extends ConsumerWidget {
  const _ActiveAccountChip({required this.repo});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final async = ref.watch(repoActiveProfileProvider(repo));
    final current = async.valueOrNull;
    final label = current?.username ?? 'no account';
    final color = current == null ? p.fg2 : p.fg1;
    return InkWell(
      onTap: () => _switch(context, ref, current: current),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.account_circle_outlined, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ]),
    );
  }

  Future<void> _switch(
    BuildContext context,
    WidgetRef ref, {
    required AuthProfile? current,
  }) async {
    final host = await ref
            .read(authResolverProvider)
            .hostFromRepo(repo, 'origin') ??
        'github.com';
    if (!context.mounted) return;
    final chosen = await AccountSwitcherDialog.show(
      context,
      host: host,
      contextMessage: 'Pick which saved account this repo should use.',
      currentProfileId: current?.id,
    );
    if (chosen == null) return;
    await ref
        .read(appSettingsProvider.notifier)
        .setAuthBinding(repo.id.value, chosen.id);
  }
}
