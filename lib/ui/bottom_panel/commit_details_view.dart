import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/main_view_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/scroll_request_provider.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/domain/commits/gpg_signature_status.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/author_avatar.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:intl/intl.dart';

/// Headline metadata for the details panel — author/committer/parents.
final _commitInfoProvider = FutureProvider.family
    .autoDispose<CommitInfo?, ({RepoLocation repo, CommitSha sha})>((
      ref,
      key,
    ) async {
      final git = ref.watch(gitReadOperationsProvider);
      final commits = await git
          .getCommits(key.repo, CommitQuery(refSpec: key.sha.value, take: 1))
          .toList();
      return commits.isEmpty ? null : commits.first;
    });

/// Full commit body, fetched separately so the bulk graph load doesn't pay
/// for it.  Cached per (repo, sha) and disposed when the details view
/// stops watching this commit.
final _commitFullMessageProvider = FutureProvider.family
    .autoDispose<String?, ({RepoLocation repo, CommitSha sha})>((ref, key) {
      return ref
          .watch(gitReadOperationsProvider)
          .getCommitFullMessage(key.repo, key.sha);
    });

class CommitDetailsView extends ConsumerWidget {
  const CommitDetailsView({required this.repo, required this.sha, super.key});
  final RepoLocation repo;
  final CommitSha sha;

  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final key = (repo: repo, sha: sha);
    final async = ref.watch(_commitInfoProvider(key));
    final messageAsync = ref.watch(_commitFullMessageProvider(key));
    return async.when(
      // Keep the commit details visible during background reloads.
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: TextStyle(color: palette.accentErr)),
      ),
      data: (c) {
        if (c == null) return const SizedBox.shrink();
        final fullMessage = messageAsync.value ?? c.summary;
        final (summary, body) = _splitMessage(fullMessage);
        final sameSignature = _sameSignature(c.author, c.committer);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Hero(
                summary: summary,
                sha: c.sha,
                signatureStatus: c.signatureStatus,
              ),
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
  const _Hero({
    required this.summary,
    required this.sha,
    required this.signatureStatus,
  });
  final String summary;
  final CommitSha sha;
  final GpgSignatureStatus signatureStatus;

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
        _SignatureBadge(status: signatureStatus),
        const SizedBox(width: 8),
        _ShaPill(sha: sha),
      ],
    );
  }
}

class _SignatureBadge extends StatelessWidget {
  const _SignatureBadge({required this.status});
  final GpgSignatureStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (icon, color) = switch (status) {
      GpgSignatureStatus.good => (
        Icons.verified_user_outlined,
        palette.accentCurrent,
      ),
      GpgSignatureStatus.unsigned => (
        Icons.shield_outlined,
        palette.fg3,
      ),
      GpgSignatureStatus.unknownValidity ||
      GpgSignatureStatus.expiredSignature ||
      GpgSignatureStatus.expiredKey ||
      GpgSignatureStatus.missingKey => (
        Icons.gpp_maybe_outlined,
        palette.accentWarn,
      ),
      GpgSignatureStatus.bad || GpgSignatureStatus.revokedKey => (
        Icons.gpp_bad_outlined,
        palette.accentErr,
      ),
    };
    return Tooltip(
      message: 'GPG: ${status.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              status.label,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShaPill extends StatefulWidget {
  const _ShaPill({required this.sha});
  final CommitSha sha;

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
    await Future<void>.delayed(const Duration(milliseconds: 900));
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  color: _justCopied ? palette.accentCurrent : palette.fg2,
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
  const _PersonRow({
    required this.role,
    required this.signature,
    required this.date,
  });
  final String role;
  final CommitSignature signature;
  final String date;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        AuthorAvatar(name: signature.name, email: signature.email, size: 28),
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
  const _ParentsRow({required this.parents, required this.repo});
  final List<CommitSha> parents;
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    if (parents.isEmpty) {
      return Row(
        children: [
          const _Label('Parents'),
          Text(
            '(root commit)',
            style: TextStyle(
              color: palette.fg3,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }
    return Row(
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
  const _ParentPill({required this.sha, required this.ref});
  final CommitSha sha;
  final WidgetRef ref;

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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _hover ? palette.bg4 : palette.bg2,
            border: Border.all(
              color: _hover ? palette.borderStrong : palette.border,
            ),
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
  const _Label(this.text);
  final String text;
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
  const _MessageBlock({required this.body});
  final String body;

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
