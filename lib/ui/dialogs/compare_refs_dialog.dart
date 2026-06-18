import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/diff/image_preview.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/diff_syntax.dart';
import 'package:gitopen/ui/common/image_diff_view.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/diff_preview_pane.dart'
    show DiffHeader, HunkBlock;
import 'package:intl/intl.dart';

typedef _Key = ({RepoLocation repo, CommitSha from, CommitSha to});

final _divergenceProvider = FutureProvider.family
    .autoDispose<({int left, int right}), _Key>(
      (ref, key) => ref
          .watch(gitReadOperationsProvider)
          .countDivergence(key.repo, key.from, key.to),
    );

/// Commits reachable only from `from` (left list). Capped at 100.
final _onlyFromProvider =
    FutureProvider.family.autoDispose<List<CommitInfo>, _Key>(
  (ref, key) => ref
      .watch(gitReadOperationsProvider)
      .getCommits(
        key.repo,
        CommitQuery(refSpec: '${key.to.value}..${key.from.value}', take: 100),
      )
      .toList(),
);

/// Commits reachable only from `to` (right list). Capped at 100.
final _onlyToProvider =
    FutureProvider.family.autoDispose<List<CommitInfo>, _Key>(
      (ref, key) => ref
          .watch(gitReadOperationsProvider)
          .getCommits(
            key.repo,
            CommitQuery(
              refSpec: '${key.from.value}..${key.to.value}',
              take: 100,
            ),
          )
          .toList(),
    );

final _compareDiffProvider =
    FutureProvider.family.autoDispose<DiffResult, _Key>(
      (ref, key) => ref
          .watch(gitReadOperationsProvider)
          .getDiff(key.repo, DiffSpecCommitVsCommit(key.from, key.to)),
    );

/// Two-ref comparison: divergence counts, the two unique-commit lists and
/// the combined `from..to` diff.
class CompareRefsDialog extends ConsumerWidget {
  const CompareRefsDialog({
    required this.repo,
    required this.from,
    required this.to,
    super.key,
  });
  final RepoLocation repo;
  final Branch from;
  final Branch to;

  /// Both branches must have a [Branch.tipSha]; callers guard.
  static Future<void> show(
    BuildContext context, {
    required RepoLocation repo,
    required Branch from,
    required Branch to,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => CompareRefsDialog(repo: repo, from: from, to: to),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final key = (repo: repo, from: from.tipSha!, to: to.tipSha!);
    final divergence = ref.watch(_divergenceProvider(key));
    return AppDialog(
      title: 'Compare ${from.name} ⟷ ${to.name}',
      width: 920,
      content: SizedBox(
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _CommitListColumn(
                      title:
                          'Only on ${from.name} '
                          '(${divergence.value?.left ?? '…'})',
                      provider: _onlyFromProvider(key),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CommitListColumn(
                      title:
                          'Only on ${to.name} '
                          '(${divergence.value?.right ?? '…'})',
                      provider: _onlyToProvider(key),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'CHANGES (${from.name} → ${to.name})',
              style: TextStyle(
                color: palette.fg3,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _CompareDiff(diffKey: key)),
          ],
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

class _CommitListColumn extends ConsumerWidget {
  const _CommitListColumn({required this.title, required this.provider});
  final String title;
  final FutureProvider<List<CommitInfo>> provider;

  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(provider);
    return Container(
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: palette.bg3,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: palette.fg1,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: TextStyle(color: palette.accentErr, fontSize: 11.5),
                ),
              ),
              data: (commits) => commits.isEmpty
                  ? Center(
                      child: Text(
                        'No unique commits',
                        style: TextStyle(
                          color: palette.fg3,
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: commits.length,
                      itemBuilder: (_, i) {
                        final c = commits[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Text(
                                c.sha.short(),
                                style: TextStyle(
                                  color: palette.accentRemote,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  c.summary,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.fg0,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _dateFmt.format(c.author.when.toLocal()),
                                style: TextStyle(
                                  color: palette.fg3,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareDiff extends ConsumerWidget {
  const _CompareDiff({required this.diffKey});
  final _Key diffKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(_compareDiffProvider(diffKey));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Error: $e',
          style: TextStyle(color: palette.accentErr, fontSize: 11.5),
        ),
      ),
      data: (d) => d.files.isEmpty
          ? Center(
              child: Text(
                'No changes between the two refs',
                style: TextStyle(
                  color: palette.fg3,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          : ListView(
              children: [
                for (final f in d.files) ...[
                  DiffHeader(path: f.path, fileDiff: f),
                  if (f.isBinary)
                    isImagePath(f.path)
                        ? ImageDiffView(
                            repo: diffKey.repo,
                            oldPath: f.oldPath ?? f.path,
                            newPath: f.path,
                            oldRevision: FileRevisionAtCommit(diffKey.from),
                            newRevision: FileRevisionAtCommit(diffKey.to),
                          )
                        : Padding(
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
                    for (final h in f.hunks)
                      HunkBlock(hunk: h, language: languageForPath(f.path)),
                ],
              ],
            ),
    );
  }
}
