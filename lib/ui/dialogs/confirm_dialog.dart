import 'package:flutter/material.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class ConfirmDialog extends StatelessWidget {

  const ConfirmDialog({
    required this.title, required this.body, super.key,
    this.confirmLabel,
    this.dangerous = false,
  });
  final String title;
  final String body;
  final String? confirmLabel;
  final bool dangerous;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String body,
    String? confirmLabel,
    bool dangerous = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        dangerous: dangerous,
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AppDialog(
      title: title,
      width: 420,
      content: Text(
        body,
        style: TextStyle(color: palette.fg1, fontSize: 12.5, height: 1.4),
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, false),
          // Destructive confirmations default focus to the safe choice.
          autofocus: dangerous,
        ),
        if (dangerous) AppButton.danger(
                label: confirmLabel ?? 'OK',
                onPressed: () => Navigator.pop(context, true),
              ) else AppButton.primary(
                label: confirmLabel ?? 'OK',
                onPressed: () => Navigator.pop(context, true),
                autofocus: true,
              ),
      ],
    );
  }
}
