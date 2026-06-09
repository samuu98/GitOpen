import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/reflog_entry.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Read-only HEAD reflog viewer. Clicking an entry reveals that commit in
/// the graph (when it is still reachable from a ref) and closes the dialog.
class ReflogDialog extends ConsumerWidget {
  const ReflogDialog({required this.repo, super.key});
  final RepoLocation repo;

  static Future<void> show(BuildContext context, RepoLocation repo) =>
      showDialog(
        context: context,
        builder: (_) => ReflogDialog(repo: repo),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return AppDialog(
      title: 'Reflog',
      subtitle: 'Where HEAD has been — useful to recover lost commits',
      width: 640,
      content: SizedBox(
        height: 380,
        child: FutureBuilder<List<ReflogEntry>>(
          future: ref.read(gitReadOperationsProvider).getReflog(repo),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Text(
                  '${snap.error}',
                  style: TextStyle(color: palette.accentErr, fontSize: 12),
                ),
              );
            }
            final entries = snap.data ?? const <ReflogEntry>[];
            if (entries.isEmpty) {
              return Center(
                child: Text(
                  'No reflog entries yet.',
                  style: TextStyle(
                    color: palette.fg2,
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              );
            }
            return ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                return InkWell(
                  onTap: () {
                    revealCommit(ref, e.sha);
                    Navigator.pop(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 86,
                          child: Text(
                            e.selector,
                            style: TextStyle(
                              color: palette.fg2,
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 70,
                          child: Text(
                            e.sha.short(),
                            style: TextStyle(
                              color: palette.accentCurrent,
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.message,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: palette.fg1, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        AppButton.secondary(
          label: 'Close',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
