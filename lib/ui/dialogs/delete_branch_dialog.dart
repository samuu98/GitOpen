import 'package:flutter/material.dart';
import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// What the user chose to delete in [DeleteBranchDialog].
class DeleteBranchSelection {
  const DeleteBranchSelection({
    required this.deleteLocal,
    required this.deleteRemote,
  });
  final bool deleteLocal;
  final bool deleteRemote;

  bool get any => deleteLocal || deleteRemote;
}

/// Confirms deletion of a branch's local and/or remote side. Each present side
/// is a checkbox, checked by default; the local side is disabled when it is the
/// checked-out branch.
class DeleteBranchDialog extends StatefulWidget {
  const DeleteBranchDialog({required this.targets, super.key});
  final BranchDeletionTargets targets;

  static Future<DeleteBranchSelection?> show(
    BuildContext context, {
    required BranchDeletionTargets targets,
  }) {
    return showDialog<DeleteBranchSelection>(
      context: context,
      builder: (_) => DeleteBranchDialog(targets: targets),
    );
  }

  @override
  State<DeleteBranchDialog> createState() => _DeleteBranchDialogState();
}

class _DeleteBranchDialogState extends State<DeleteBranchDialog> {
  late bool _local =
      widget.targets.localName != null && !widget.targets.localIsCurrent;
  late bool _remote = widget.targets.remoteRef != null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final t = widget.targets;
    return AppDialog(
      title: 'Delete branch',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.localName != null)
            CheckboxListTile(
              value: _local,
              onChanged: t.localIsCurrent
                  ? null
                  : (v) => setState(() => _local = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Local branch ${t.localName}',
                style: TextStyle(color: palette.fg0, fontSize: 13),
              ),
              subtitle: t.localIsCurrent
                  ? Text(
                      'Current branch — checkout another first',
                      style: TextStyle(color: palette.fg3, fontSize: 11),
                    )
                  : null,
            ),
          if (t.remoteRef != null)
            CheckboxListTile(
              value: _remote,
              onChanged: (v) => setState(() => _remote = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Remote branch ${t.remoteRef}',
                style: TextStyle(color: palette.fg0, fontSize: 13),
              ),
              subtitle: Text(
                'Deletes it on the server (push --delete)',
                style: TextStyle(color: palette.fg3, fontSize: 11),
              ),
            ),
        ],
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AppButton.danger(
          label: 'Delete',
          onPressed: (_local || _remote)
              ? () => Navigator.pop(
                    context,
                    DeleteBranchSelection(
                      deleteLocal: _local,
                      deleteRemote: _remote,
                    ),
                  )
              : null,
        ),
      ],
    );
  }
}
