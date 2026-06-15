import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class ActivityPanel extends ConsumerWidget {
  const ActivityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationsProvider);
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    return Dialog(
      backgroundColor: palette.bg1,
      child: SizedBox(
        width: 560,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: spacing.panel,
              child: Row(
                children: [
                  Text(
                    'Activity',
                    style: TextStyle(
                      color: palette.fg0,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        ref.read(operationsProvider.notifier).clearCompleted(),
                    child: const Text('Clear completed'),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: palette.fg1),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
            Expanded(
              child: ListView.builder(
                itemCount: ops.length,
                itemBuilder: (_, i) => _Row(op: ops[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.op});
  final RunningOperation op;
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final op = widget.op;
    IconData icon;
    Color color;
    switch (op.status) {
      case OperationStatus.running:
      case OperationStatus.pending:
        icon = Icons.refresh;
        color = palette.accentRemote;
      case OperationStatus.success:
        icon = Icons.check_circle;
        color = palette.accentCurrent;
      case OperationStatus.failed:
        icon = Icons.error;
        color = palette.accentErr;
      case OperationStatus.cancelled:
        icon = Icons.block;
        color = palette.fg2;
    }
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Text(
                    op.label,
                    style: TextStyle(color: palette.fg0, fontSize: 12.5),
                  ),
                ),
                Text(
                  op.startedAt.toLocal().toString().substring(11, 19),
                  style: TextStyle(color: palette.fg3, fontSize: 11),
                ),
              ],
            ),
            if (_expanded && op.stderrTail.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: spacing.xs, left: 22),
                child: Container(
                  padding: EdgeInsets.all(spacing.sm),
                  decoration: BoxDecoration(
                    color: palette.bg2,
                    borderRadius: radii.rowRadius,
                  ),
                  child: Text(
                    op.stderrTail.join('\n'),
                    style: TextStyle(
                      color: palette.fg1,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            if (_expanded && op.errorMessage != null)
              Padding(
                padding: EdgeInsets.only(top: spacing.xs, left: 22),
                child: Text(
                  op.errorMessage!,
                  style: TextStyle(color: palette.accentErr, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
