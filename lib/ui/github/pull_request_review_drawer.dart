import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/github/github_mutation.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final class QueuedReviewComment {
  const QueuedReviewComment({
    required this.path,
    required this.body,
    required this.line,
    required this.side,
  });

  final String path;
  final String body;
  final int line;
  final String side;

  DraftReviewComment toRequest() => DraftReviewComment(
    path: path,
    body: body,
    line: line,
    side: side,
  );
}

class PullRequestReviewDrawer extends ConsumerStatefulWidget {
  const PullRequestReviewDrawer({
    required this.repo,
    required this.slug,
    required this.token,
    required this.number,
    required this.queuedComments,
    required this.onClearQueuedComments,
    super.key,
  });

  final RepoLocation repo;
  final RepoSlug slug;
  final String token;
  final int number;
  final List<QueuedReviewComment> queuedComments;
  final VoidCallback onClearQueuedComments;

  @override
  ConsumerState<PullRequestReviewDrawer> createState() =>
      _PullRequestReviewDrawerState();
}

class _PullRequestReviewDrawerState
    extends ConsumerState<PullRequestReviewDrawer> {
  final _summary = TextEditingController();
  final _issueComment = TextEditingController();
  String? _error;
  bool _pending = false;

  @override
  void dispose() {
    _summary.dispose();
    _issueComment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Review',
              style: TextStyle(
                color: palette.fg0,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.queuedComments.length} queued line comment(s)',
              style: TextStyle(color: palette.fg3, fontSize: 11.5),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const Key('review-summary-body'),
              controller: _summary,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Review summary',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                AppButton.primary(
                  onPressed: _pending ? null : () => _submitReview('COMMENT'),
                  label: _pending ? 'Submitting…' : 'Comment',
                ),
                AppButton.secondary(
                  onPressed: _pending ? null : () => _submitReview('APPROVE'),
                  label: 'Approve',
                ),
                AppButton.secondary(
                  onPressed: _pending
                      ? null
                      : () => _submitReview('REQUEST_CHANGES'),
                  label: 'Request changes',
                ),
              ],
            ),
            const Divider(height: 18),
            Text(
              'Conversation',
              style: TextStyle(
                color: palette.fg0,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const Key('issue-comment-body'),
              controller: _issueComment,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Conversation comment',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton.primary(
                onPressed: _pending ? null : _addIssueComment,
                label: 'Add comment',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: palette.accentErr, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submitReview(String event) async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await runGitHubMutation<PullRequestReview>(
        ref,
        repo: widget.repo,
        key: 'pr/${widget.number}/review',
        slug: widget.slug,
        token: widget.token,
        pullRequest: widget.number,
        reviewData: true,
        successMessage: 'Review submitted.',
        action: () => ref
            .read(gitHubApiProvider)
            .createReview(
              widget.slug,
              widget.number,
              SubmitReviewRequest(
                event: event,
                body: _summary.text.trim(),
                comments: [
                  for (final comment in widget.queuedComments)
                    comment.toRequest(),
                ],
              ),
              token: widget.token,
            ),
      );
      if (!mounted) return;
      _summary.clear();
      widget.onClearQueuedComments();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _addIssueComment() async {
    if (_pending) return;
    final body = _issueComment.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await runGitHubMutation<IssueCommentInfo>(
        ref,
        repo: widget.repo,
        key: 'pr/${widget.number}/comment',
        slug: widget.slug,
        token: widget.token,
        pullRequest: widget.number,
        reviewData: true,
        successMessage: 'Comment added.',
        action: () => ref
            .read(gitHubApiProvider)
            .createIssueComment(
              widget.slug,
              widget.number,
              body,
              token: widget.token,
            ),
      );
      if (!mounted) return;
      _issueComment.clear();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }
}

Future<QueuedReviewComment?> showLineCommentDialog(
  BuildContext context, {
  required String path,
  required int line,
  required String side,
}) => showDialog<QueuedReviewComment>(
  context: context,
  builder: (context) => _LineCommentDialog(
    path: path,
    line: line,
    side: side,
  ),
);

class _LineCommentDialog extends StatefulWidget {
  const _LineCommentDialog({
    required this.path,
    required this.line,
    required this.side,
  });

  final String path;
  final int line;
  final String side;

  @override
  State<_LineCommentDialog> createState() => _LineCommentDialogState();
}

class _LineCommentDialogState extends State<_LineCommentDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Comment on line ${widget.line}',
      content: TextField(
        key: const Key('review-line-comment-body'),
        controller: _controller,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(labelText: 'Comment'),
      ),
      actions: [
        AppButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Cancel',
        ),
        AppButton.primary(
          onPressed: () {
            final body = _controller.text.trim();
            if (body.isEmpty) return;
            Navigator.of(context).pop(
              QueuedReviewComment(
                path: widget.path,
                body: body,
                line: widget.line,
                side: widget.side,
              ),
            );
          },
          label: 'Queue comment',
        ),
      ],
    );
  }
}
