import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Picks a local branch and a remote for `git push <remote> <branch>`.
class PushBranchDialog {
  static Future<({String branch, String remote})?> show(
    BuildContext context,
    WidgetRef ref,
    RepoLocation repo,
  ) async {
    final read = ref.read(gitReadOperationsProvider);
    final branches = await read.getLocalBranches(repo);
    final remotes = await read.getRemotes(repo);
    if (!context.mounted || branches.isEmpty || remotes.isEmpty) return null;

    final current = branches
        .where((b) => b.isCurrent)
        .map((b) => b.name)
        .firstOrNull;
    var branch = current ?? branches.first.name;
    var remote = remotes.first.name;

    return showDialog<({String branch, String remote})>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setState) => AppDialog(
            title: 'Push branch',
            width: 420,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: branch,
                  decoration: appInputDecoration(ctx, label: 'Branch'),
                  dropdownColor: palette.bg2,
                  style: TextStyle(color: palette.fg0, fontSize: 13),
                  items: [
                    for (final b in branches)
                      DropdownMenuItem(value: b.name, child: Text(b.name)),
                  ],
                  onChanged: (v) => setState(() => branch = v ?? branch),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: remote,
                  decoration: appInputDecoration(ctx, label: 'Remote'),
                  dropdownColor: palette.bg2,
                  style: TextStyle(color: palette.fg0, fontSize: 13),
                  items: [
                    for (final r in remotes)
                      DropdownMenuItem(value: r.name, child: Text(r.name)),
                  ],
                  onChanged: (v) => setState(() => remote = v ?? remote),
                ),
              ],
            ),
            actions: [
              AppButton.secondary(
                label: 'Cancel',
                onPressed: () => Navigator.pop(ctx),
              ),
              AppButton.primary(
                label: 'Push',
                onPressed: () =>
                    Navigator.pop(ctx, (branch: branch, remote: remote)),
              ),
            ],
          ),
        );
      },
    );
  }
}
