import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'app_dialog.dart';

enum CheckoutAction { discard, stash, keep }

/// Shown before a checkout when the working tree is dirty. Asks the user
/// what to do with the pending changes: discard, stash, or keep (attempt
/// checkout as-is; git will refuse if files would be overwritten).
class CheckoutChangesDialog extends StatelessWidget {
  final String targetRef;
  const CheckoutChangesDialog({super.key, required this.targetRef});

  static Future<CheckoutAction?> show(
      BuildContext context, String targetRef) async {
    return showDialog<CheckoutAction>(
      context: context,
      builder: (_) => CheckoutChangesDialog(targetRef: targetRef),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AppDialog(
      title: 'Switch to "$targetRef"',
      width: 460,
      content: Text(
        'You have uncommitted changes. What would you like to do with them?',
        style: TextStyle(color: palette.fg1, fontSize: 12.5, height: 1.4),
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AppButton.danger(
          label: 'Discard',
          onPressed: () => Navigator.pop(context, CheckoutAction.discard),
        ),
        AppButton.secondary(
          label: 'Stash',
          onPressed: () => Navigator.pop(context, CheckoutAction.stash),
        ),
        AppButton.primary(
          label: 'Keep & switch',
          onPressed: () => Navigator.pop(context, CheckoutAction.keep),
        ),
      ],
    );
  }
}
