import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/github/github_pr_diff.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/github/github_api_state.dart';
import 'package:gitopen/ui/github/github_providers.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class PullRequestFilesView extends ConsumerStatefulWidget {
  const PullRequestFilesView({
    required this.slug,
    required this.token,
    required this.number,
    required this.onLineCommentRequested,
    super.key,
  });

  final RepoSlug slug;
  final String token;
  final int number;
  final void Function(String path, int line, String side)
  onLineCommentRequested;

  @override
  ConsumerState<PullRequestFilesView> createState() =>
      _PullRequestFilesViewState();
}

class _PullRequestFilesViewState extends ConsumerState<PullRequestFilesView> {
  String? _selectedPath;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final key = (
      slug: widget.slug,
      token: widget.token,
      number: widget.number,
    );
    final async = ref.watch(githubPullRequestFilesProvider(key));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => GitHubApiErrorView(
        error: e,
        onRetry: () => ref.invalidate(githubPullRequestFilesProvider(key)),
      ),
      data: (files) {
        if (files.isEmpty) {
          return Center(
            child: Text(
              'No changed files',
              style: TextStyle(color: palette.fg3, fontSize: 12.5),
            ),
          );
        }
        final selected = files.firstWhere(
          (f) => f.filename == _selectedPath,
          orElse: () => files.first,
        );
        final fileList = _FilesList(
          files: files,
          selected: selected.filename,
          onSelect: (path) => setState(() => _selectedPath = path),
        );
        final patch = _PatchView(
          file: selected,
          onLineCommentRequested: widget.onLineCommentRequested,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 420) {
              return Column(
                children: [
                  SizedBox(height: 90, child: fileList),
                  Container(height: 1, color: palette.border),
                  Expanded(child: patch),
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 240, child: fileList),
                Container(width: 1, color: palette.border),
                Expanded(child: patch),
              ],
            );
          },
        );
      },
    );
  }
}

class _FilesList extends StatelessWidget {
  const _FilesList({
    required this.files,
    required this.selected,
    required this.onSelect,
  });

  final List<PullRequestFile> files;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: files.length,
      itemBuilder: (_, index) {
        final file = files[index];
        final isSelected = file.filename == selected;
        return Material(
          color: isSelected ? palette.bgAccent : palette.bg1,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => onSelect(file.filename),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.filename,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.fg0, fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '+${file.additions} -${file.deletions}',
                    style: TextStyle(
                      color: palette.fg3,
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PatchView extends StatelessWidget {
  const _PatchView({
    required this.file,
    required this.onLineCommentRequested,
  });

  final PullRequestFile file;
  final void Function(String path, int line, String side)
  onLineCommentRequested;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final lines = parseGitHubPatch(file.patch);
    GitHubPatchLine? lineTwo;
    for (final line in lines) {
      if (line.commentLine == 2 && line.isCommentable) {
        lineTwo = line;
        break;
      }
    }
    final lineTwoCommentLine = lineTwo?.commentLine;
    final lineTwoSide = lineTwo?.side;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: palette.bg2,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Patch: ${file.filename}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.fg1, fontSize: 12),
                ),
              ),
              if (lineTwoCommentLine != null && lineTwoSide != null)
                AppIconButton(
                  tooltip: 'Comment on line 2',
                  icon: Icons.add_comment_outlined,
                  onPressed: () => onLineCommentRequested(
                    file.filename,
                    lineTwoCommentLine,
                    lineTwoSide,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? Center(
                  child: Text(
                    'Patch not available',
                    style: TextStyle(color: palette.fg3, fontSize: 12.5),
                  ),
                )
              : ListView(
                  children: [
                    for (final line in lines)
                      _PatchLineRow(
                        file: file,
                        line: line,
                        onLineCommentRequested: onLineCommentRequested,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PatchLineRow extends StatelessWidget {
  const _PatchLineRow({
    required this.file,
    required this.line,
    required this.onLineCommentRequested,
  });

  final PullRequestFile file;
  final GitHubPatchLine line;
  final void Function(String path, int line, String side)
  onLineCommentRequested;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bg = line.isAddition
        ? palette.accentCurrent.withValues(alpha: 0.10)
        : line.isDeletion
        ? palette.accentErr.withValues(alpha: 0.12)
        : Colors.transparent;
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Text(
              line.oldLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.fg3,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 38,
            child: Text(
              line.newLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.fg3,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              line.content,
              style: TextStyle(
                color: palette.fg0,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          if (line.isCommentable && line.commentLine != null)
            AppIconButton(
              tooltip: 'Comment on line ${line.commentLine}',
              icon: Icons.add_comment_outlined,
              onPressed: () => onLineCommentRequested(
                file.filename,
                line.commentLine!,
                line.side,
              ),
            ),
        ],
      ),
    );
  }
}
