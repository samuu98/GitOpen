import 'package:flutter/material.dart';
import 'package:gitopen/application/github/github_models.dart';

final class PullRequestCreateFormResult {
  const PullRequestCreateFormResult(this.request);

  final CreatePullRequestRequest request;
}

final class PullRequestEditFormResult {
  const PullRequestEditFormResult(this.request);

  final UpdatePullRequestRequest request;
}

final class PullRequestMergeFormResult {
  const PullRequestMergeFormResult(this.request);

  final MergePullRequestRequest request;
}

Future<PullRequestCreateFormResult?> showCreatePullRequestDialog(
  BuildContext context,
) {
  return showDialog<PullRequestCreateFormResult>(
    context: context,
    builder: (_) => const _CreatePullRequestDialog(),
  );
}

Future<PullRequestEditFormResult?> showEditPullRequestDialog(
  BuildContext context,
  PullRequestDetail detail,
) {
  return showDialog<PullRequestEditFormResult>(
    context: context,
    builder: (_) => _EditPullRequestDialog(detail: detail),
  );
}

Future<PullRequestMergeFormResult?> showMergePullRequestDialog(
  BuildContext context,
) {
  return showDialog<PullRequestMergeFormResult>(
    context: context,
    builder: (_) => const _MergePullRequestDialog(),
  );
}

class _CreatePullRequestDialog extends StatefulWidget {
  const _CreatePullRequestDialog();

  @override
  State<_CreatePullRequestDialog> createState() =>
      _CreatePullRequestDialogState();
}

class _CreatePullRequestDialogState extends State<_CreatePullRequestDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _base = TextEditingController(text: 'main');
  final _head = TextEditingController();
  bool _draft = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _base.dispose();
    _head.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create PR'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('create-pr-title'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              key: const Key('create-pr-body'),
              controller: _body,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Body'),
            ),
            TextField(
              key: const Key('create-pr-base'),
              controller: _base,
              decoration: const InputDecoration(labelText: 'Base branch'),
            ),
            TextField(
              key: const Key('create-pr-head'),
              controller: _head,
              decoration: const InputDecoration(labelText: 'Head branch'),
            ),
            CheckboxListTile(
              value: _draft,
              contentPadding: EdgeInsets.zero,
              title: const Text('Draft'),
              onChanged: (value) => setState(() => _draft = value ?? false),
            ),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }

  void _submit() {
    final title = _title.text.trim();
    final base = _base.text.trim();
    final head = _head.text.trim();
    if (title.isEmpty || base.isEmpty || head.isEmpty) {
      setState(() => _error = 'Title, base, and head are required.');
      return;
    }
    Navigator.of(context).pop(
      PullRequestCreateFormResult(
        CreatePullRequestRequest(
          title: title,
          body: _body.text.trim(),
          head: head,
          base: base,
          draft: _draft,
        ),
      ),
    );
  }
}

class _EditPullRequestDialog extends StatefulWidget {
  const _EditPullRequestDialog({required this.detail});

  final PullRequestDetail detail;

  @override
  State<_EditPullRequestDialog> createState() => _EditPullRequestDialogState();
}

class _EditPullRequestDialogState extends State<_EditPullRequestDialog> {
  late final _title = TextEditingController(text: widget.detail.title);
  late final _body = TextEditingController(text: widget.detail.body);
  late final _base = TextEditingController(text: widget.detail.baseRef);
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _base.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit PR'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _body,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Body'),
            ),
            TextField(
              controller: _base,
              decoration: const InputDecoration(labelText: 'Base branch'),
            ),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _submit() {
    final title = _title.text.trim();
    final base = _base.text.trim();
    if (title.isEmpty || base.isEmpty) {
      setState(() => _error = 'Title and base are required.');
      return;
    }
    Navigator.of(context).pop(
      PullRequestEditFormResult(
        UpdatePullRequestRequest(
          title: title,
          body: _body.text.trim(),
          base: base,
        ),
      ),
    );
  }
}

class _MergePullRequestDialog extends StatefulWidget {
  const _MergePullRequestDialog();

  @override
  State<_MergePullRequestDialog> createState() =>
      _MergePullRequestDialogState();
}

class _MergePullRequestDialogState extends State<_MergePullRequestDialog> {
  PullRequestMergeMethod _method = PullRequestMergeMethod.merge;
  final _title = TextEditingController();
  final _message = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Merge PR'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Merge'),
                  selected: _method == PullRequestMergeMethod.merge,
                  onSelected: (_) =>
                      setState(() => _method = PullRequestMergeMethod.merge),
                ),
                ChoiceChip(
                  label: const Text('Squash'),
                  selected: _method == PullRequestMergeMethod.squash,
                  onSelected: (_) =>
                      setState(() => _method = PullRequestMergeMethod.squash),
                ),
                ChoiceChip(
                  label: const Text('Rebase'),
                  selected: _method == PullRequestMergeMethod.rebase,
                  onSelected: (_) =>
                      setState(() => _method = PullRequestMergeMethod.rebase),
                ),
              ],
            ),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Commit title'),
            ),
            TextField(
              controller: _message,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Commit message'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            PullRequestMergeFormResult(
              MergePullRequestRequest(
                method: _method,
                commitTitle: _title.text.trim(),
                commitMessage: _message.text.trim(),
              ),
            ),
          ),
          child: const Text('Confirm merge'),
        ),
      ],
    );
  }
}
