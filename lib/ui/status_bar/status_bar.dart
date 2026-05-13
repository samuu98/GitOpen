import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/git/repo_state_provider.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';
import '../../domain/refs/branch.dart';
import '../../domain/repositories/repo_location.dart';
import '../theme/app_palette.dart';
import '../operations/activity_panel.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final active =
        workspaces.where((w) => w.location.id == activeId).cast<dynamic>().firstOrNull;

    if (active == null) {
      return Container(height: 22, color: p.bg3);
    }
    final repo = active.location as RepoLocation;
    final branchesAsync = ref.watch(_branchesProvider(repo));
    final inProgressAsync = ref.watch(repoStateProvider(repo));
    final ops = ref.watch(operationsProvider);
    final running = ops.where((o) => o.status == OperationStatus.running).length;

    return Container(
      height: 22,
      color: p.bg3,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        branchesAsync.when(
          loading: () => Text('loading...', style: TextStyle(color: p.fg2, fontSize: 11)),
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
              if (cur.ahead > 0)
                Text(' ↑${cur.ahead}', style: TextStyle(color: p.accentCurrent, fontSize: 11)),
              if (cur.behind > 0)
                Text(' ↓${cur.behind}', style: TextStyle(color: p.accentTag, fontSize: 11)),
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
        InkWell(
          onTap: () => showDialog(
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

final _branchesProvider =
    FutureProvider.family.autoDispose<List<Branch>, RepoLocation>((ref, repo) async {
  return ref.watch(gitReadOperationsProvider).getBranches(repo);
});
