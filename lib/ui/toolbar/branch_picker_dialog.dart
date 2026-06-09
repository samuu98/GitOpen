import 'package:flutter/material.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Filterable single-select branch list used by the toolbar's switch/delete
/// flows. Pops with the selected branch name, or null on cancel.
class BranchPickerDialog extends StatefulWidget {
  const BranchPickerDialog({
    required this.title,
    required this.branches,
    super.key,
  });
  final String title;
  final List<String> branches;

  @override
  State<BranchPickerDialog> createState() => _BranchPickerDialogState();
}

class _BranchPickerDialogState extends State<BranchPickerDialog> {
  String? _selected;
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final filtered = widget.branches
        .where((b) => b.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return AppDialog(
      title: widget.title,
      width: 380,
      content: SizedBox(
        height: 320,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              style: TextStyle(color: palette.fg0, fontSize: 13),
              decoration: appInputDecoration(context, label: 'Filter…')
                  .copyWith(
                prefixIcon:
                    Icon(Icons.search, size: 16, color: palette.fg2),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final b = filtered[i];
                  final selected = _selected == b;
                  return InkWell(
                    onTap: () => setState(() => _selected = b),
                    child: Container(
                      color:
                          selected ? palette.bgAccent : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Text(
                        b,
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? palette.fg0 : palette.fg1,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AppButton.primary(
          label: 'OK',
          onPressed: _selected != null
              ? () => Navigator.pop(context, _selected)
              : null,
        ),
      ],
    );
  }
}
