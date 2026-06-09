import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/discard_changes.dart';
import 'package:gitopen/ui/working_copy/file_row.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

class FileList extends ConsumerWidget {
  const FileList({
    required this.repo,
    required this.unstaged,
    required this.staged,
    super.key,
  });
  final RepoLocation repo;
  final List<WorkingFileEntry> unstaged;
  final List<WorkingFileEntry> staged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(children: [
      Header(
        title: 'Unstaged (${unstaged.length})',
        actions: [
          HeaderAction(
            'Discard all',
            unstaged.isEmpty
                ? null
                : () => confirmAndDiscardAll(context, ref, repo, unstaged),
            danger: true,
          ),
          HeaderAction(
            'Stage all',
            unstaged.isEmpty
                ? null
                : () async {
                    await ref
                        .read(gitWriteOperationsProvider)
                        .stageFiles(repo, unstaged.map((e) => e.path).toList());
                    ref.invalidate(workingCopyStatusProvider(repo));
                  },
          ),
        ],
      ),
      for (final e in unstaged) FileRow(repo: repo, entry: e, isStaged: false),
      Header(
        title: 'Staged (${staged.length})',
        actions: [
          HeaderAction(
            'Unstage all',
            staged.isEmpty
                ? null
                : () async {
                    await ref
                        .read(gitWriteOperationsProvider)
                        .unstageFiles(repo, staged.map((e) => e.path).toList());
                    ref.invalidate(workingCopyStatusProvider(repo));
                  },
          ),
        ],
      ),
      for (final e in staged) FileRow(repo: repo, entry: e, isStaged: true),
    ]);
  }
}

// ---------------------------------------------------------------------------

class HeaderAction {
  const HeaderAction(this.label, this.onPressed, {this.danger = false});
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
}

class Header extends StatelessWidget {
  const Header({required this.title, this.actions = const [], super.key});
  final String title;
  final List<HeaderAction> actions;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: palette.bg2,
      child: Row(children: [
        Text(
          title,
          style: TextStyle(
            color: palette.fg1,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        for (final a in actions)
          TextButton(
            onPressed: a.onPressed,
            style: a.danger
                ? TextButton.styleFrom(foregroundColor: palette.accentErr)
                : null,
            child: Text(a.label),
          ),
      ]),
    );
  }
}
