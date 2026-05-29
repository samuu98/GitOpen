import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/main_view_provider.dart';
import '../../application/providers.dart';
import '../../application/repo_revision.dart';
import '../../domain/repositories/repo_location.dart';
import '../theme/app_palette.dart';

final repoStatusProvider = FutureProvider.family.autoDispose((ref, RepoLocation r) async {
  ref.watch(repoRevisionProvider(r));
  final git = ref.watch(gitReadOperationsProvider);
  return git.getStatus(r);
});

class LocalChangesRow extends ConsumerWidget {
  final RepoLocation repo;
  const LocalChangesRow({super.key, required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(repoStatusProvider(repo));
    return async.when(
      data: (status) {
        if (status.entries.isEmpty) return const SizedBox.shrink();
        final count = status.entries.length;
        final palette = AppPalette.of(context);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              ref.read(mainViewProvider.notifier).state = MainView.changes;
              ref.read(selectedCommitShaProvider.notifier).state = null;
            },
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Icon(Icons.edit_note, size: 16, color: palette.accentTag),
                const SizedBox(width: 8),
                Text('Local Changes ($count)',
                    style: TextStyle(
                      color: palette.accentTag,
                      fontSize: 12.5, fontWeight: FontWeight.w600,
                    )),
              ]),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}
