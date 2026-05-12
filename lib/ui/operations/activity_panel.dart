import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';

class ActivityPanel extends ConsumerWidget {
  const ActivityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationsProvider);
    return Dialog(
      backgroundColor: const Color(0xFF1F1F23),
      child: SizedBox(
        width: 560,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text('Activity', style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => ref.read(operationsProvider.notifier).clearCompleted(),
                    child: const Text('Clear completed'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Color(0xFFB8B8BC)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF313137)),
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
  final RunningOperation op;
  const _Row({required this.op});
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final op = widget.op;
    IconData icon; Color color;
    switch (op.status) {
      case OperationStatus.running:
      case OperationStatus.pending:
        icon = Icons.refresh; color = const Color(0xFF6FA8DC); break;
      case OperationStatus.success:
        icon = Icons.check_circle; color = const Color(0xFF4EC9B0); break;
      case OperationStatus.failed:
        icon = Icons.error; color = const Color(0xFFC4314B); break;
      case OperationStatus.cancelled:
        icon = Icons.block; color = const Color(0xFF888892); break;
    }
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(op.label, style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12.5))),
              Text(op.startedAt.toLocal().toString().substring(11, 19),
                  style: const TextStyle(color: Color(0xFF5D5D65), fontSize: 11)),
            ]),
            if (_expanded && op.stderrTail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 22),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF25252A), borderRadius: BorderRadius.circular(4)),
                  child: Text(op.stderrTail.join('\n'),
                      style: const TextStyle(color: Color(0xFFB8B8BC), fontSize: 11, fontFamily: 'monospace')),
                ),
              ),
            if (_expanded && op.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 22),
                child: Text(op.errorMessage!, style: const TextStyle(color: Color(0xFFC4314B), fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }
}
