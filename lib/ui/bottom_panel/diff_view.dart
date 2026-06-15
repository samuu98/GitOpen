import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/diff/image_preview.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/diff_syntax.dart';
import 'package:gitopen/ui/common/diff_line_row.dart';
import 'package:gitopen/ui/common/diff_prefs.dart';
import 'package:gitopen/ui/common/image_diff_view.dart';
import 'package:gitopen/ui/common/truncated_diff_banner.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final AutoDisposeFutureProviderFamily<
  DiffResult,
  ({RepoLocation repo, CommitSha sha, bool ignoreWhitespace})
>
_diffProvider = FutureProvider.family
    .autoDispose<
      DiffResult,
      ({RepoLocation repo, CommitSha sha, bool ignoreWhitespace})
    >(
      (ref, key) async {
        final git = ref.watch(gitReadOperationsProvider);
        return git.getDiff(
          key.repo,
          DiffSpecCommitVsParent(key.sha),
          ignoreWhitespace: key.ignoreWhitespace,
        );
      },
    );

/// Uncapped single-file diff, fetched when the user asks for the full
/// content of a truncated file.
final AutoDisposeFutureProviderFamily<
  FileDiff?,
  ({
    RepoLocation repo,
    CommitSha sha,
    String path,
    bool ignoreWhitespace,
  })
>
_fullFileProvider = FutureProvider.family
    .autoDispose<
      FileDiff?,
      ({
        RepoLocation repo,
        CommitSha sha,
        String path,
        bool ignoreWhitespace,
      })
    >((ref, key) async {
      final git = ref.watch(gitReadOperationsProvider);
      final result = await git.getDiffForFile(
        key.repo,
        DiffSpecCommitVsParent(key.sha),
        key.path,
        ignoreWhitespace: key.ignoreWhitespace,
      );
      return result.files.isEmpty ? null : result.files.first;
    });

class DiffView extends ConsumerWidget {
  const DiffView({required this.repo, required this.sha, super.key});
  final RepoLocation repo;
  final CommitSha sha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final ignoreWhitespace = ref.watch(ignoreWhitespaceProvider);
    final async = ref.watch(
      _diffProvider(
        (repo: repo, sha: sha, ignoreWhitespace: ignoreWhitespace),
      ),
    );
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: TextStyle(color: palette.accentErr)),
      ),
      data: (d) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                WordDiffToggle(),
                SizedBox(width: 4),
                IgnoreWhitespaceToggle(),
                SizedBox(width: 4),
                SplitDiffToggle(),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: spacing.panel,
              itemCount: d.files.length,
              itemBuilder: (_, i) =>
                  _FileDiffBlock(file: d.files[i], repo: repo, sha: sha),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileDiffBlock extends ConsumerStatefulWidget {
  const _FileDiffBlock({
    required this.file,
    required this.repo,
    required this.sha,
  });
  final FileDiff file;
  final RepoLocation repo;
  final CommitSha sha;

  @override
  ConsumerState<_FileDiffBlock> createState() => _FileDiffBlockState();
}

class _FileDiffBlockState extends ConsumerState<_FileDiffBlock> {
  /// User asked for the uncapped version of this (truncated) file.
  bool _full = false;

  FileDiff get file => widget.file;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final language = languageForPath(file.path);
    final full = _full
        ? ref.watch(
            _fullFileProvider(
              (
                repo: widget.repo,
                sha: widget.sha,
                path: file.path,
                ignoreWhitespace: ref.watch(ignoreWhitespaceProvider),
              ),
            ),
          )
        : null;
    final shown = full?.valueOrNull ?? file;
    return Container(
      margin: EdgeInsets.only(bottom: spacing.md),
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border.all(color: palette.border),
        borderRadius: radii.panelRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          if (file.isBinary)
            isImagePath(file.path)
                ? ImageDiffView(
                    repo: widget.repo,
                    oldPath: file.oldPath ?? file.path,
                    newPath: file.path,
                    oldRevision: FileRevisionParentOfCommit(widget.sha),
                    newRevision: FileRevisionAtCommit(widget.sha),
                  )
                : Padding(
                    padding: EdgeInsets.all(spacing.md),
                    child: Text(
                      'Binary file (no preview)',
                      style: TextStyle(
                        color: palette.fg2,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
          else ...[
            for (final h in shown.hunks) _hunk(context, h, language),
            if (full != null && full.isLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (shown.truncated && !_full)
              TruncatedDiffBanner(
                onLoadFull: () => setState(() => _full = true),
              ),
          ],
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
          child: Text(
            h.header,
            style: TextStyle(
              color: palette.fg2,
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              fontFamily: 'monospace',
            ),
          ),
        ),
        HunkLines(lines: h.lines, language: language),
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
