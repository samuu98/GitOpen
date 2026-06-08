import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/main_view_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class LocalChangesRow extends ConsumerWidget {
  const LocalChangesRow({required this.repo, super.key});
  final RepoLocation repo;

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
