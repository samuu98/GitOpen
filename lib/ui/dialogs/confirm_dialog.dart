import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'app_dialog.dart';

class ConfirmDialog extends StatelessWidget {
  final String title;
  final String body;
  final String? confirmLabel;
  final bool dangerous;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    this.confirmLabel,
    this.dangerous = false,
  });

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
        ),
        dangerous
            ? AppButton.danger(
                label: confirmLabel ?? 'OK',
                onPressed: () => Navigator.pop(context, true),
                autofocus: true,
              )
            : AppButton.primary(
                label: confirmLabel ?? 'OK',
                onPressed: () => Navigator.pop(context, true),
                autofocus: true,
              ),
      ],
    );
  }
}
