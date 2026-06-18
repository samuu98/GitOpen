import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/blame/blame_line.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/author_avatar.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:intl/intl.dart';

/// Key for the file-history / blame providers — a (repo, path) pair.
typedef FileKey = ({RepoLocation repo, String path});

/// Commits that touched a given path, newest first (`git log --follow`).
final fileHistoryProvider =
    FutureProvider.family.autoDispose<List<CommitInfo>, FileKey>(
        (ref, key) async {
  final git = ref.watch(gitReadOperationsProvider);
  // Cap at a sane page; the dialog is for browsing, not full archaeology.
  return git.getFileHistory(key.repo, key.path, take: 200);
});

/// Per-line blame for a path at HEAD (`git blame --porcelain`).
final fileBlameProvider =
    FutureProvider.family.autoDispose<List<BlameLine>, FileKey>(
        (ref, key) async {
  final git = ref.watch(gitReadOperationsProvider);
  return git.getBlame(key.repo, key.path);
});

/// Self-contained dialog surfacing a file's commit history and per-line blame.
///
/// Opened from the file tree (or anywhere with a repo + path).  Tabs between
/// "History" (commit rows) and "Blame" (line gutter).  Purely read-only — it
/// does not mutate any existing app state.
class FileHistoryDialog extends StatefulWidget {
  const FileHistoryDialog({
    required this.repo,
    required this.path,
    super.key,
  });

  final RepoLocation repo;
  final String path;

  /// Convenience launcher used by call sites.
  static Future<void> show(
    BuildContext context, {
    required RepoLocation repo,
    required String path,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => FileHistoryDialog(repo: repo, path: path),
    );
  }

  @override
  State<FileHistoryDialog> createState() => _FileHistoryDialogState();
}

class _FileHistoryDialogState extends State<FileHistoryDialog> {
  bool _blame = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fileName = widget.path.contains('/')
        ? widget.path.substring(widget.path.lastIndexOf('/') + 1)
        : widget.path;

    return Dialog(
      backgroundColor: palette.bg1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(
              fileName: fileName,
              path: widget.path,
              blame: _blame,
              onSelect: (v) => setState(() => _blame = v),
              onClose: () => Navigator.of(context).maybePop(),
            ),
            Flexible(
              child: _blame
                  ? _BlameBody(repo: widget.repo, path: widget.path)
                  : _HistoryBody(repo: widget.repo, path: widget.path),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.fileName,
    required this.path,
    required this.blame,
    required this.onSelect,
    required this.onClose,
  });
  final String fileName;
  final String path;
  final bool blame;
  final ValueChanged<bool> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      decoration: BoxDecoration(
        color: palette.bg3,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 16, color: palette.fg2),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: path,
                  child: Text(
                    fileName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.fg0,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 16, color: palette.fg2),
                splashRadius: 16,
                tooltip: 'Close',
                onPressed: onClose,
              ),
            ],
          ),
          Row(
            children: [
              _SegTab(
                label: 'History',
                active: !blame,
                onTap: () => onSelect(false),
              ),
              _SegTab(
                label: 'Blame',
                active: blame,
                onTap: () => onSelect(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegTab extends StatelessWidget {
  const _SegTab({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? palette.accentCurrent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? palette.fg0 : palette.fg2,
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _HistoryBody extends ConsumerWidget {
  const _HistoryBody({required this.repo, required this.path});
  final RepoLocation repo;
  final String path;

  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(fileHistoryProvider((repo: repo, path: path)));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: TextStyle(color: palette.accentErr)),
      ),
      data: (commits) {
        if (commits.isEmpty) {
          return Center(
            child: Text(
              'No history for this file.',
              style: TextStyle(
                  color: palette.fg2, fontStyle: FontStyle.italic),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: commits.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: palette.border),
          itemBuilder: (_, i) => _CommitRow(
            commit: commits[i],
            date: _dateFmt.format(commits[i].author.when.toLocal()),
          ),
        );
      },
    );
  }
}

class _CommitRow extends StatelessWidget {
  const _CommitRow({required this.commit, required this.date});
  final CommitInfo commit;
  final String date;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthorAvatar(
            name: commit.author.name,
            email: commit.author.email,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  commit.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.fg0,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${commit.author.name} · $date',
                  style: TextStyle(color: palette.fg2, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _ShaTag(sha: commit.sha.short()),
        ],
      ),
    );
  }
}

class _ShaTag extends StatelessWidget {
  const _ShaTag({required this.sha});
  final String sha;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: palette.bg2,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        sha,
        style: TextStyle(
          color: palette.accentRemote,
          fontFamily: 'monospace',
          fontSize: 11,
        ),
      ),
    );
  }
}

class _BlameBody extends ConsumerWidget {
  const _BlameBody({required this.repo, required this.path});
  final RepoLocation repo;
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(fileBlameProvider((repo: repo, path: path)));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: TextStyle(color: palette.accentErr)),
      ),
      data: (lines) {
        if (lines.isEmpty) {
          return Center(
            child: Text(
              'Nothing to blame.',
              style: TextStyle(
                  color: palette.fg2, fontStyle: FontStyle.italic),
            ),
          );
        }
        return Scrollbar(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: lines.length,
            itemBuilder: (_, i) => _BlameRow(line: lines[i]),
          ),
        );
      },
    );
  }
}

class _BlameRow extends StatelessWidget {
  const _BlameRow({required this.line});
  final BlameLine line;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gutter: short sha + author.
          Tooltip(
            message: '${line.sha.value}\n${line.authorName}',
            child: SizedBox(
              width: 150,
              child: Row(
                children: [
                  Text(
                    line.sha.short(),
                    style: TextStyle(
                      color: palette.accentRemote,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      line.authorName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.fg3, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '${line.lineNumber}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.fg3,
                fontFamily: 'monospace',
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              line.content.isEmpty ? ' ' : line.content,
              style: TextStyle(
                color: palette.fg1,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
