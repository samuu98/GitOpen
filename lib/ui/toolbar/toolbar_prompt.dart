import 'package:flutter/material.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Single-line text prompt shared between the toolbar dropdowns.
Future<String?> appPromptText(BuildContext context, String title,
    {required String label, String? initial}) async {
  final ctl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final palette = AppPalette.of(ctx);
      return AppDialog(
        title: title,
        width: 420,
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: TextStyle(color: palette.fg0, fontSize: 13),
          decoration: appInputDecoration(ctx, label: label),
          onSubmitted: (_) => Navigator.pop(ctx, ctl.text),
        ),
        actions: [
          AppButton.secondary(
              label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
          AppButton.primary(
              label: 'OK', onPressed: () => Navigator.pop(ctx, ctl.text)),
        ],
      );
    },
  );
  ctl.dispose();
  return result;
}
