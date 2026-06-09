import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/diff_syntax.dart';
import 'package:gitopen/ui/common/diff_line_row.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final AutoDisposeFutureProviderFamily<DiffResult,
        ({RepoLocation repo, CommitSha sha})> _diffProvider =
    FutureProvider.family.autoDispose<DiffResult,
        ({RepoLocation repo, CommitSha sha})>((ref, key) async {
  final git = ref.watch(gitReadOperationsProvider);
  return git.getDiff(key.repo, DiffSpecCommitVsParent(key.sha));
});

class DiffView extends ConsumerWidget {
  const DiffView({required this.repo, required this.sha, super.key});
  final RepoLocation repo;
  final CommitSha sha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(_diffProvider((repo: repo, sha: sha)));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e',
          style: TextStyle(color: palette.accentErr))),
      data: (d) => ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: d.files.length,
        itemBuilder: (_, i) => _FileDiffBlock(file: d.files[i]),
      ),
    );
  }
}

class _FileDiffBlock extends StatelessWidget {
  const _FileDiffBlock({required this.file});
  final FileDiff file;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final language = languageForPath(file.path);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          if (file.isBinary)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Binary file (no preview)',
                style: TextStyle(
                  color: palette.fg2,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            for (final h in file.hunks) _hunk(context, h, language),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final palette = AppPalette.of(context);
    final pathLabel = file.oldPath != null && file.oldPath != file.path
        ? '${file.oldPath} → ${file.path}'
        : file.path;
    return Container(
      decoration: BoxDecoration(
        color: palette.bg3,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _KindBadge(kind: file.changeKind),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              pathLabel,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.fg0, fontSize: 12),
            ),
          ),
          Text(
            '+${file.linesAdded} -${file.linesDeleted}',
            style: TextStyle(color: palette.fg2, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _hunk(BuildContext context, DiffHunk h, String? language) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: palette.bg2,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(h.header,
              style: TextStyle(
                  color: palette.fg2,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  fontFamily: 'monospace')),
        ),
        for (final line in h.lines)
          DiffLineRow(line: line, language: language),
      ],
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});
  final dynamic kind;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final (bg, fg) = _palette(kind.toString(), p);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        kind.toString().split('.').last.toUpperCase(),
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  (Color, Color) _palette(String s, AppPalette p) {
    if (s.contains('added')) {
      return (p.accentCurrent.withValues(alpha: 0.18), p.accentCurrent);
    }
    if (s.contains('deleted')) {
      return (p.accentErr.withValues(alpha: 0.18), p.accentErr);
    }
    if (s.contains('modified')) {
      return (p.accentTag.withValues(alpha: 0.18), p.accentTag);
    }
    if (s.contains('renamed')) {
      return (p.accentRemote.withValues(alpha: 0.18), p.accentRemote);
    }
    return (p.bg4, p.fg1);
  }
}
