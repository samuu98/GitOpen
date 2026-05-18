import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'app_dialog.dart';

enum RemoteDialogMode { add, editUrl, rename }

class RemoteDialogResult {
  final String name;
  final String url;
  const RemoteDialogResult({required this.name, required this.url});
}

class RemoteDialog extends StatefulWidget {
  final RemoteDialogMode mode;
  final String? initialName;
  final String? initialUrl;

  const RemoteDialog({
    super.key,
    required this.mode,
    this.initialName,
    this.initialUrl,
  });

  static Future<RemoteDialogResult?> showAdd(BuildContext context) =>
      showDialog<RemoteDialogResult>(
        context: context,
        builder: (_) => const RemoteDialog(mode: RemoteDialogMode.add),
      );

  static Future<RemoteDialogResult?> showEditUrl(
          BuildContext context, String name, String currentUrl) =>
      showDialog<RemoteDialogResult>(
        context: context,
        builder: (_) => RemoteDialog(
          mode: RemoteDialogMode.editUrl,
          initialName: name,
          initialUrl: currentUrl,
        ),
      );

  static Future<RemoteDialogResult?> showRename(
          BuildContext context, String currentName) =>
      showDialog<RemoteDialogResult>(
        context: context,
        builder: (_) => RemoteDialog(
          mode: RemoteDialogMode.rename,
          initialName: currentName,
        ),
      );

  @override
  State<RemoteDialog> createState() => _RemoteDialogState();
}

class _RemoteDialogState extends State<RemoteDialog> {
  late final TextEditingController _nameCtl =
      TextEditingController(text: widget.initialName ?? '');
  late final TextEditingController _urlCtl =
      TextEditingController(text: widget.initialUrl ?? '');

  @override
  void dispose() {
    _nameCtl.dispose();
    _urlCtl.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
        RemoteDialogMode.add => 'Add remote',
        RemoteDialogMode.editUrl => 'Edit remote URL',
        RemoteDialogMode.rename => 'Rename remote',
      };

  String get _confirmLabel => switch (widget.mode) {
        RemoteDialogMode.add => 'Add',
        RemoteDialogMode.editUrl => 'Save',
        RemoteDialogMode.rename => 'Rename',
      };

  bool get _valid {
    final name = _nameCtl.text.trim();
    final url = _urlCtl.text.trim();
    switch (widget.mode) {
      case RemoteDialogMode.add:
        return name.isNotEmpty && !name.contains(' ') && url.isNotEmpty;
      case RemoteDialogMode.editUrl:
        return url.isNotEmpty;
      case RemoteDialogMode.rename:
        return name.isNotEmpty &&
            !name.contains(' ') &&
            name != widget.initialName;
    }
  }

  void _submit() {
    if (!_valid) return;
    Navigator.pop(
      context,
      RemoteDialogResult(
        name: _nameCtl.text.trim(),
        url: _urlCtl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final showName = widget.mode != RemoteDialogMode.editUrl;
    final showUrl = widget.mode != RemoteDialogMode.rename;
    final nameEnabled = widget.mode != RemoteDialogMode.editUrl;

    return AppDialog(
      title: _title,
      width: 460,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showName)
            TextField(
              controller: _nameCtl,
              autofocus: widget.mode != RemoteDialogMode.editUrl,
              enabled: nameEnabled,
              style: TextStyle(color: palette.fg0, fontSize: 13),
              decoration: appInputDecoration(context,
                  label: 'Name', hint: 'origin'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
          if (showName && showUrl) const SizedBox(height: 12),
          if (showUrl)
            TextField(
              controller: _urlCtl,
              autofocus: widget.mode == RemoteDialogMode.editUrl,
              style: TextStyle(color: palette.fg0, fontSize: 13),
              decoration: appInputDecoration(
                context,
                label: 'URL',
                hint: 'https://github.com/user/repo.git',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
        ],
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AppButton.primary(
          label: _confirmLabel,
          onPressed: _valid ? _submit : null,
        ),
      ],
    );
  }
}
