import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/active_workspace_provider.dart';
import '../../application/git/git_read_operations.dart';
import '../../application/main_view_provider.dart';
import '../../application/providers.dart';
import '../../application/scroll_request_provider.dart';
import '../../domain/commits/commit_info.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/commits/commit_signature.dart';
import '../../domain/repositories/repo_location.dart';
import '../common/author_avatar.dart';
import '../theme/app_palette.dart';

/// Headline metadata for the details panel — author/committer/parents.
final _commitInfoProvider = FutureProvider.family.autoDispose<CommitInfo?,
    ({RepoLocation repo, CommitSha sha})>((ref, key) async {
  final git = ref.watch(gitReadOperationsProvider);
  final commits = await git
      .getCommits(key.repo, CommitQuery(refSpec: key.sha.value, take: 1))
      .toList();
  return commits.isEmpty ? null : commits.first;
});

/// Full commit body, fetched separately so the bulk graph load doesn't pay
/// for it.  Cached per (repo, sha) and disposed when the details view
/// stops watching this commit.
final _commitFullMessageProvider = FutureProvider.family.autoDispose<String?,
    ({RepoLocation repo, CommitSha sha})>((ref, key) {
  return ref
      .watch(gitReadOperationsProvider)
      .getCommitFullMessage(key.repo, key.sha);
});

class CommitDetailsView extends ConsumerWidget {
  final RepoLocation repo;
  final CommitSha sha;
  const CommitDetailsView({super.key, required this.repo, required this.sha});

  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final key = (repo: repo, sha: sha);
    final async = ref.watch(_commitInfoProvider(key));
    final messageAsync = ref.watch(_commitFullMessageProvider(key));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: TextStyle(color: palette.accentErr)),
      ),
      data: (c) {
        if (c == null) return const SizedBox.shrink();
        final fullMessage = messageAsync.valueOrNull ?? c.summary;
        final (summary, body) = _splitMessage(fullMessage);
        final sameSignature = _sameSignature(c.author, c.committer);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Hero(summary: summary, sha: c.sha),
              const SizedBox(height: 16),
              _PersonRow(
                role: 'authored',
                signature: c.author,
                date: _dateFmt.format(c.author.when.toLocal()),
              ),
              if (!sameSignature) ...[
                const SizedBox(height: 10),
                _PersonRow(
                  role: 'committed',
                  signature: c.committer,
                  date: _dateFmt.format(c.committer.when.toLocal()),
                ),
              ],
              const SizedBox(height: 16),
              _ParentsRow(parents: c.parentShas, repo: repo),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 16),
                _MessageBlock(body: body),
              ],
            ],
          ),
        );
      },
    );
  }
}

bool _sameSignature(CommitSignature a, CommitSignature b) =>
    a.name == b.name && a.email == b.email;

(String summary, String body) _splitMessage(String message) {
  final trimmed = message.trim();
  final nl = trimmed.indexOf('\n');
  if (nl < 0) return (trimmed, '');
  return (trimmed.substring(0, nl).trim(), trimmed.substring(nl + 1).trim());
}

class _Hero extends StatelessWidget {
  final String summary;
  final CommitSha sha;
  const _Hero({required this.summary, required this.sha});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectableText(
            summary,
            style: TextStyle(
              color: palette.fg0,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(width: 12),
        _ShaPill(sha: sha),
      ],
    );
  }
}

class _ShaPill extends StatefulWidget {
  final CommitSha sha;
  const _ShaPill({required this.sha});

  @override
  State<_ShaPill> createState() => _ShaPillState();
}

class _ShaPillState extends State<_ShaPill> {
  bool _hover = false;
  bool _justCopied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.sha.value));
    if (!mounted) return;
    setState(() => _justCopied = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _justCopied = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: _justCopied ? 'Copied!' : 'Copy full SHA',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: _copy,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _hover ? palette.bg4 : palette.bg2,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _justCopied ? Icons.check : Icons.tag,
                  size: 11,
                  color: _justCopied
                      ? palette.accentCurrent
                      : palette.fg2,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.sha.short(),
                  style: TextStyle(
                    color: palette.fg0,
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final String role;
  final CommitSignature signature;
  final String date;
  const _PersonRow({
    required this.role,
    required this.signature,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AuthorAvatar(
            name: signature.name, email: signature.email, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      signature.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.fg0,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    role,
                    style: TextStyle(
                      color: palette.fg3,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              SelectableText(
                signature.email,
                style: TextStyle(color: palette.fg2, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          date,
          style: TextStyle(
            color: palette.fg2,
            fontSize: 11.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ParentsRow extends ConsumerWidget {
  final List<CommitSha> parents;
  final RepoLocation repo;
  const _ParentsRow({required this.parents, required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    if (parents.isEmpty) {
      return Row(
        children: [
          _Label('Parents'),
          Text('(root commit)',
              style: TextStyle(
                  color: palette.fg3,
                  fontSize: 12,
                  fontStyle: FontStyle.italic)),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Label(parents.length == 1 ? 'Parent' : 'Parents'),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in parents) _ParentPill(sha: p, ref: ref),
            ],
          ),
        ),
      ],
    );
  }
}

class _ParentPill extends StatefulWidget {
  final CommitSha sha;
  final WidgetRef ref;
  const _ParentPill({required this.sha, required this.ref});

  @override
  State<_ParentPill> createState() => _ParentPillState();
}

class _ParentPillState extends State<_ParentPill> {
  bool _hover = false;

  void _reveal() {
    widget.ref.read(mainViewProvider.notifier).state = MainView.graph;
    widget.ref.read(selectedCommitShaProvider.notifier).state = widget.sha;
    widget.ref.read(scrollRequestProvider.notifier).state = widget.sha;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _reveal,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _hover ? palette.bg4 : palette.bg2,
            border: Border.all(
                color: _hover ? palette.borderStrong : palette.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.sha.short(),
            style: TextStyle(
              color: palette.accentRemote,
              fontFamily: 'monospace',
              fontSize: 11.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: 72,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: palette.fg3,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  final String body;
  const _MessageBlock({required this.body});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bg2,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        body,
        style: TextStyle(
          color: palette.fg1,
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.55,
        ),
      ),
    );
  }
}
