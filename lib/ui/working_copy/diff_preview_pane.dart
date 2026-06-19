import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/diff/image_preview.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/diff_syntax.dart';
import 'package:gitopen/ui/common/diff_line_row.dart';
import 'package:gitopen/ui/common/diff_prefs.dart';
import 'package:gitopen/ui/common/image_diff_view.dart';
import 'package:gitopen/ui/common/truncated_diff_banner.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

// ---------------------------------------------------------------------------
// Diff preview pane — renders the selected file's diff.
// ---------------------------------------------------------------------------

/// Uncapped single-file working-copy diff for "Load full diff".
final _fullWorkingFileProvider = FutureProvider.family
    .autoDispose<FileDiff?, ({RepoLocation repo, String path, bool staged})>((
      ref,
      key,
    ) async {
      final git = ref.watch(gitReadOperationsProvider);
      final spec = key.staged
          ? const DiffSpecIndexVsHead()
          : const DiffSpecWorkingTreeVsIndex();
      final result = await git.getDiffForFile(key.repo, spec, key.path);
      return result.files.isEmpty ? null : result.files.first;
    });

class DiffPreviewPane extends ConsumerStatefulWidget {
  const DiffPreviewPane({required this.repo, super.key});
  final RepoLocation repo;

  @override
  ConsumerState<DiffPreviewPane> createState() => _DiffPreviewPaneState();
}

class _DiffPreviewPaneState extends ConsumerState<DiffPreviewPane> {
  /// Selection (path, staged) the user expanded past the truncation cap.
  ({String path, bool staged})? _fullFor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final repo = widget.repo;
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
        // Keep the current diff visible during background reloads.
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Diff error: $e',
            style: TextStyle(color: palette.accentErr),
          ),
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
            if (isImagePath(sel.path)) {
              return ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  DiffHeader(path: sel.path, fileDiff: fileDiff),
                  ImageDiffView(
                    repo: repo,
                    oldPath: fileDiff.oldPath ?? sel.path,
                    newPath: sel.path,
                    oldRevision: sel.staged
                        ? const FileRevisionHead()
                        : const FileRevisionIndex(),
                    newRevision: sel.staged
                        ? const FileRevisionIndex()
                        : const FileRevisionWorkingTree(),
                  ),
                ],
              );
            }
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
          final wantFull =
              _fullFor != null &&
              _fullFor == (path: sel.path, staged: sel.staged);
          final full = wantFull
              ? ref.watch(
                  _fullWorkingFileProvider((
                    repo: repo,
                    path: sel.path,
                    staged: sel.staged,
                  )),
                )
              : null;
          final shown = full?.value ?? fileDiff;
          final language = languageForPath(sel.path);
          return SelectionArea(
            // Selectable like normal text; chrome (header, hunk headers,
            // gutters, +/- prefix) is excluded via SelectionContainer.disabled.
            child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              DiffHeader(path: sel.path, fileDiff: shown),
              for (final h in shown.hunks)
                HunkBlock(hunk: h, language: language),
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
              if (shown.truncated && !wantFull)
                TruncatedDiffBanner(
                  onLoadFull: () => setState(
                    () => _fullFor = (path: sel.path, staged: sel.staged),
                  ),
                ),
            ],
          ),
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
    // Header is chrome — excluded from text selection.
    return SelectionContainer.disabled(
      child: Container(
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
            child: Text(
              path,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.fg0, fontSize: 12),
            ),
          ),
          Text(
            '+${fileDiff.linesAdded} -${fileDiff.linesDeleted}',
            style: TextStyle(color: palette.fg2, fontSize: 11),
          ),
          const SizedBox(width: 8),
          const WordDiffToggle(),
          const SizedBox(width: 4),
          const SplitDiffToggle(),
        ],
      ),
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
            child: SelectionContainer.disabled(
              child: Text(
                hunk.header,
                style: TextStyle(
                  color: palette.fg2,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          HunkLines(
            lines: hunk.lines,
            language: language,
            gutterWidth: 34,
            prefixWidth: 12,
          ),
        ],
      ),
    );
  }
}
