import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/diff/diff_hunk.dart';
import '../../domain/diff/diff_line.dart';
import '../../domain/diff/diff_result.dart';
import '../../domain/diff/diff_spec.dart';
import '../../domain/diff/file_diff.dart';
import '../../domain/repositories/repo_location.dart';
import '../common/skeleton.dart';
import '../theme/app_palette.dart';
import 'inline_diff.dart';

final _diffProvider = FutureProvider.family
    .autoDispose<DiffResult, ({RepoLocation repo, CommitSha sha})>((ref, key) async {
  final git = ref.watch(gitReadOperationsProvider);
  return git.getDiff(key.repo, DiffSpecCommitVsParent(key.sha));
});

class DiffView extends ConsumerWidget {
  final RepoLocation repo;
  final CommitSha sha;
  const DiffView({super.key, required this.repo, required this.sha});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(_diffProvider((repo: repo, sha: sha)));
    return async.when(
      loading: () => const SkeletonList(rows: 14, rowHeight: 10, gap: 10),
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
  final FileDiff file;
  const _FileDiffBlock({required this.file});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
              child: Text('Binary file (no preview)',
                  style: TextStyle(color: palette.fg2, fontStyle: FontStyle.italic)),
            )
          else
            for (final h in file.hunks) _hunk(context, h),
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

  Widget _hunk(BuildContext context, DiffHunk h) {
    final palette = AppPalette.of(context);
    final segments = _inlineSegments(h.lines);
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
        for (var i = 0; i < h.lines.length; i++)
          _DiffLineRow(line: h.lines[i], segments: segments[i]),
      ],
    );
  }

  /// Pairs each run of deletions with the addition run that follows it and
  /// computes a word-level diff per pair, so changed lines highlight only the
  /// bits that actually differ. Returns segments keyed by line index.
  Map<int, List<InlineSegment>> _inlineSegments(List<DiffLine> lines) {
    final result = <int, List<InlineSegment>>{};
    var i = 0;
    while (i < lines.length) {
      if (lines[i].kind != DiffLineKind.deletion) {
        i++;
        continue;
      }
      final delStart = i;
      while (i < lines.length && lines[i].kind == DiffLineKind.deletion) {
        i++;
      }
      final delEnd = i;
      final addStart = i;
      while (i < lines.length && lines[i].kind == DiffLineKind.addition) {
        i++;
      }
      final addEnd = i;
      final pairs =
          (delEnd - delStart) < (addEnd - addStart) ? delEnd - delStart : addEnd - addStart;
      for (var k = 0; k < pairs; k++) {
        final oldLine = lines[delStart + k].content;
        final newLine = lines[addStart + k].content;
        if (oldLine.isEmpty && newLine.isEmpty) continue;
        final (oldSegs, newSegs) = computeInlineDiff(oldLine, newLine);
        result[delStart + k] = oldSegs;
        result[addStart + k] = newSegs;
      }
    }
    return result;
  }
}

class _DiffLineRow extends StatelessWidget {
  final DiffLine line;

  /// Word-level segments for changed lines; null for context lines or when no
  /// counterpart line exists. Changed segments get a stronger highlight.
  final List<InlineSegment>? segments;
  const _DiffLineRow({required this.line, this.segments});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    Color bg;
    Color tokenBg;
    String prefix;
    switch (line.kind) {
      case DiffLineKind.addition:
        bg = palette.accentCurrent.withValues(alpha: 0.10);
        tokenBg = palette.accentCurrent.withValues(alpha: 0.30);
        prefix = '+';
        break;
      case DiffLineKind.deletion:
        bg = palette.accentErr.withValues(alpha: 0.12);
        tokenBg = palette.accentErr.withValues(alpha: 0.30);
        prefix = '-';
        break;
      case DiffLineKind.context:
        bg = Colors.transparent;
        tokenBg = Colors.transparent;
        prefix = ' ';
        break;
    }
    final baseStyle = TextStyle(
        color: palette.fg0, fontSize: 12, fontFamily: 'monospace');
    final segs = segments;
    final Widget content;
    if (segs == null || segs.length < 2) {
      content = Text(
        line.content,
        style: baseStyle,
        softWrap: false,
        overflow: TextOverflow.clip,
      );
    } else {
      content = Text.rich(
        TextSpan(children: [
          for (final s in segs)
            TextSpan(
              text: s.text,
              style: s.changed
                  ? baseStyle.copyWith(
                      background: Paint()..color = tokenBg)
                  : baseStyle,
            ),
        ]),
        softWrap: false,
        overflow: TextOverflow.clip,
      );
    }
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 40, child: Text(line.oldLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(color: palette.fg3, fontSize: 11, fontFamily: 'monospace'))),
          const SizedBox(width: 6),
          SizedBox(width: 40, child: Text(line.newLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(color: palette.fg3, fontSize: 11, fontFamily: 'monospace'))),
          const SizedBox(width: 6),
          SizedBox(width: 14, child: Text(prefix,
              style: TextStyle(color: palette.fg3, fontSize: 12, fontFamily: 'monospace'))),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  final dynamic kind;
  const _KindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final (bg, fg) = _palette(kind.toString(), p);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
      child: Text(
        kind.toString().split('.').last.toUpperCase(),
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.3),
      ),
    );
  }

  (Color, Color) _palette(String s, AppPalette p) {
    if (s.contains('added'))    return (p.accentCurrent.withValues(alpha: 0.18), p.accentCurrent);
    if (s.contains('deleted'))  return (p.accentErr.withValues(alpha: 0.18), p.accentErr);
    if (s.contains('modified')) return (p.accentTag.withValues(alpha: 0.18), p.accentTag);
    if (s.contains('renamed'))  return (p.accentRemote.withValues(alpha: 0.18), p.accentRemote);
    return (p.bg4, p.fg1);
  }
}
