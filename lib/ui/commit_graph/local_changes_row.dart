import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';

final repoStatusProvider = FutureProvider.family.autoDispose((ref, RepoLocation r) async {
  final git = ref.watch(gitReadOperationsProvider);
  return git.getStatus(r);
});

class LocalChangesRow extends ConsumerWidget {
  final RepoLocation repo;
  const LocalChangesRow({super.key, required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(repoStatusProvider(repo));
    final selected = ref.watch(localChangesSelectedProvider);
    return async.when(
      data: (status) {
        if (status.entries.isEmpty) return const SizedBox.shrink();
        final count = status.entries.length;
        return Material(
          color: selected ? const Color(0xFF094771) : Colors.transparent,
          child: InkWell(
            onTap: () {
              ref.read(localChangesSelectedProvider.notifier).state = true;
              ref.read(selectedCommitShaProvider.notifier).state = null;
            },
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                const Icon(Icons.edit_note, size: 16, color: Color(0xFFD7BA7D)),
                const SizedBox(width: 8),
                Text('Local Changes ($count)',
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFD7BA7D),
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
