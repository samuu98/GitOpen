import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/diff_syntax.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

// ---------------------------------------------------------------------------
// Diff preview pane — renders the selected file's diff.
// ---------------------------------------------------------------------------

class DiffPreviewPane extends ConsumerWidget {
  const DiffPreviewPane({required this.repo, super.key});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final sel = ref.watch(selectedFileProvider);
    if (sel == null) {
      return Container(
        color: palette.bg1,
        alignment: Alignment.center,
        child: Text(
          'Select a file to preview changes',
          style: TextStyle(
            color: palette.fg3,
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    final provider = sel.staged
        ? stagedFileDiffProvider((repo, sel.path))
        : unstagedFileDiffProvider((repo, sel.path));
    final async = ref.watch(provider);
    return ColoredBox(
      color: palette.bg1,
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Diff error: $e',
              style: TextStyle(color: palette.accentErr)),
        ),
        data: (fileDiff) {
          if (fileDiff == null) {
            return Center(
              child: Text(
                'No diff available (untracked or unchanged)',
                style: TextStyle(color: palette.fg3, fontSize: 12),
              ),
            );
          }
          if (fileDiff.isBinary) {
            return Center(
              child: Text(
                'Binary file (no preview)',
                style: TextStyle(
                  color: palette.fg2,
                  fontStyle: FontStyle.italic,
                ),
              ),
            );
          }
          final language = languageForPath(sel.path);
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              DiffHeader(path: sel.path, fileDiff: fileDiff),
              for (final h in fileDiff.hunks)
                HunkBlock(hunk: h, language: language),
            ],
          );
        },
      ),
    );
  }
}

class DiffHeader extends StatelessWidget {
  const DiffHeader({required this.path, required this.fileDiff, super.key});
  final String path;
  final FileDiff fileDiff;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.bg3,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(path,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.fg0, fontSize: 12)),
          ),
          Text(
            '+${fileDiff.linesAdded} -${fileDiff.linesDeleted}',
            style: TextStyle(color: palette.fg2, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class HunkBlock extends StatelessWidget {
  const HunkBlock({required this.hunk, this.language, super.key});
  final DiffHunk hunk;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: palette.bg2,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(hunk.header,
                style: TextStyle(
                  color: palette.fg2,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  fontFamily: 'monospace',
                )),
          ),
          for (final line in hunk.lines)
            _DiffLine(line: line, language: language),
        ],
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line, this.language});
  final DiffLine line;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final Color bg;
    final String prefix;
    switch (line.kind) {
      case DiffLineKind.addition:
        bg = palette.accentCurrent.withValues(alpha: 0.10);
        prefix = '+';
      case DiffLineKind.deletion:
        bg = palette.accentErr.withValues(alpha: 0.12);
        prefix = '-';
      case DiffLineKind.context:
        bg = Colors.transparent;
        prefix = ' ';
    }
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(line.oldLine?.toString() ?? '',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: palette.fg3, fontSize: 11, fontFamily: 'monospace')),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: Text(line.newLine?.toString() ?? '',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: palette.fg3, fontSize: 11, fontFamily: 'monospace')),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 12,
            child: Text(prefix,
                style: TextStyle(
                    color: palette.fg3, fontSize: 12, fontFamily: 'monospace')),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: buildHighlightedSpans(
                  line.content,
                  language,
                  baseColor: palette.fg0,
                ),
              ),
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }
}
