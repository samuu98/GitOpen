import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/auth/auth_profile.dart';
import '../../application/git/repo_state_provider.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';
import '../dialogs/account_switcher_dialog.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import '../operations/activity_panel.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final typo = AppTypography.of(context);
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final active =
        workspaces.where((w) => w.location.id == activeId).cast<dynamic>().firstOrNull;

    if (active == null) {
      return Container(height: 24, color: p.bg3);
    }
    final repo = active.location as RepoLocation;
    final branchesAsync = ref.watch(branchesProvider(repo));
    final statusAsync = ref.watch(repoStatusProvider(repo));
    final inProgressAsync = ref.watch(repoStateProvider(repo));
    final ops = ref.watch(operationsProvider);
    final running =
        ops.where((o) => o.status == OperationStatus.running).toList();

    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: p.bg3,
        border: Border(top: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        branchesAsync.when(
          loading: () =>
              Text('loading…', style: typo.bodySmall.copyWith(color: p.fg2)),
          // ignore: avoid_types_on_closure_parameters
          error: (Object e, StackTrace s) => const SizedBox.shrink(),
          data: (branches) {
            if (branches.isEmpty) return const SizedBox.shrink();
            final cur = branches.firstWhere(
              (b) => b.isCurrent,
              orElse: () => branches.first,
            );
            return Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.fork_right, size: 12, color: p.accentCurrent),
              const SizedBox(width: 4),
              Text(cur.name, style: typo.bodySmall.copyWith(color: p.fg0)),
              // ahead/behind for the current branch comes from RepoStatus
              // (cheap, single `git status` call), NOT from for-each-ref's
              // `upstream:track` atom which becomes O(N×commits) on repos
              // with many local branches that diverge a lot from upstream.
              if ((statusAsync.valueOrNull?.ahead ?? 0) > 0)
                Text(' ↑${statusAsync.valueOrNull!.ahead}',
                    style: typo.bodySmall.copyWith(color: p.accentCurrent)),
              if ((statusAsync.valueOrNull?.behind ?? 0) > 0)
                Text(' ↓${statusAsync.valueOrNull!.behind}',
                    style: typo.bodySmall.copyWith(color: p.accentTag)),
            ]);
          },
        ),
        const _Separator(),
        Expanded(
          child: Tooltip(
            message: 'Click to copy path',
            child: InkWell(
              onTap: () => Clipboard.setData(ClipboardData(text: repo.path)),
              child: Text(
                repo.path,
                overflow: TextOverflow.ellipsis,
                style: typo.bodySmall.copyWith(color: p.fg2),
              ),
            ),
          ),
        ),
        if (inProgressAsync.valueOrNull != null &&
            inProgressAsync.valueOrNull != InProgressOp.none) ...[
          Icon(Icons.warning_amber, size: 13, color: p.accentTag),
          const SizedBox(width: 4),
          Text(
            '${inProgressAsync.valueOrNull!.name} in progress',
            style: typo.bodySmall.copyWith(color: p.accentTag),
          ),
          const _Separator(),
        ],
        _ActiveAccountChip(repo: repo),
        const _Separator(),
        Tooltip(
          message: 'Show activity log',
          child: InkWell(
            onTap: () => showDialog(
              context: context,
              builder: (_) => const ActivityPanel(),
            ),
            child: running.isEmpty
                ? Row(children: [
                    Icon(Icons.workspaces_outline, size: 12, color: p.fg2),
                    const SizedBox(width: 4),
                    Text('idle', style: typo.bodySmall.copyWith(color: p.fg2)),
                  ])
                : _PrimaryOperation(operation: running.first,
                    extraCount: running.length - 1),
          ),
        ),
      ]),
    );
  }
}

/// Thin vertical rule between status-bar sections (VS Code style).
class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: p.borderStrong,
    );
  }
}

/// Shows the most recent running operation by name (with progress when the
/// stream reports it) instead of an opaque "2 ops" counter.
class _PrimaryOperation extends StatelessWidget {
  final RunningOperation operation;
  final int extraCount;
  const _PrimaryOperation(
      {required this.operation, required this.extraCount});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final typo = AppTypography.of(context);
    final fraction = operation.progress;
    final label = StringBuffer(operation.label);
    if (fraction != null && fraction > 0) {
      label.write(' ${(fraction * 100).round()}%');
    }
    if (extraCount > 0) label.write('  (+$extraCount more)');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 11,
        height: 11,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          value: fraction != null && fraction > 0 ? fraction : null,
          color: p.accentCurrent,
        ),
      ),
      const SizedBox(width: 6),
      Text(label.toString(),
          style: typo.bodySmall.copyWith(color: p.fg1)),
    ]);
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
  final RepoLocation repo;
  const _ActiveAccountChip({required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final typo = AppTypography.of(context);
    final async = ref.watch(repoActiveProfileProvider(repo));
    final current = async.valueOrNull;
    final missing = current == null;
    final color = missing ? p.accentTag : p.fg1;
    return Tooltip(
      message: missing
          ? 'No account bound to this repo — pushes to private remotes '
              'will fail. Click to pick one.'
          : 'Acting as ${current.username} — click to switch account',
      child: InkWell(
        onTap: () => _switch(context, ref, current: current),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            missing
                ? Icons.no_accounts_outlined
                : Icons.account_circle_outlined,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(current?.username ?? 'no account',
              style: typo.bodySmall.copyWith(color: color)),
        ]),
      ),
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
