import 'package:flutter/material.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// What the user asked for in [TagCreateDialog]: a tag [name] and an optional
/// annotation [message] — null means a lightweight tag.
final class TagCreateRequest {
  const TagCreateRequest(this.name, this.message);
  final String name;
  final String? message;
}

/// Prompts for a tag name plus an optional annotation message.
/// Returns null when cancelled (or confirmed with an empty name).
class TagCreateDialog {
  static Future<TagCreateRequest?> show(BuildContext context) {
    return showDialog<TagCreateRequest>(
      context: context,
      builder: (_) => const _TagCreateDialogContent(),
    );
  }
}

class _TagCreateDialogContent extends StatefulWidget {
  const _TagCreateDialogContent();

  @override
  State<_TagCreateDialogContent> createState() =>
      _TagCreateDialogContentState();
}

class _TagCreateDialogContentState extends State<_TagCreateDialogContent> {
  final _nameCtl = TextEditingController();
  final _messageCtl = TextEditingController();

  @override
  void dispose() {
    _nameCtl.dispose();
    _messageCtl.dispose();
    super.dispose();
  }

  TagCreateRequest? _submit() {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) return null;
    final message = _messageCtl.text.trim();
    return TagCreateRequest(name, message.isEmpty ? null : message);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AppDialog(
      title: 'Tag here',
      width: 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtl,
            autofocus: true,
            style: TextStyle(color: palette.fg0, fontSize: 13),
            decoration: appInputDecoration(context, label: 'Tag name'),
            onSubmitted: (_) => Navigator.pop(context, _submit()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageCtl,
            maxLines: 3,
            style: TextStyle(color: palette.fg0, fontSize: 13),
            decoration: appInputDecoration(
              context,
              label: 'Message (optional — creates an annotated tag)',
            ),
          ),
        ],
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AppButton.primary(
          label: 'Create tag',
          onPressed: () => Navigator.pop(context, _submit()),
        ),
      ],
    );
  }
}
