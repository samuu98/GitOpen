import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';
import 'activity_panel.dart';

class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationsProvider);
    // Take running ops + recently finished failures (last 5s) for display
    final now = DateTime.now();
    final visible = ops.where((o) {
      if (o.status == OperationStatus.running || o.status == OperationStatus.pending) { return true; }
      if (o.status == OperationStatus.failed && o.finishedAt != null
          && now.difference(o.finishedAt!) < const Duration(seconds: 10)) { return true; }
      if (o.status == OperationStatus.success && o.finishedAt != null
          && now.difference(o.finishedAt!) < const Duration(seconds: 3)) { return true; }
      return false;
    }).take(3).toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return Positioned(
      right: 12,
      bottom: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final op in visible) _ToastItem(op: op),
        ],
      ),
    );
  }
}

class _ToastItem extends ConsumerWidget {
  final RunningOperation op;
  const _ToastItem({required this.op});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isError = op.status == OperationStatus.failed;
    final isRunning = op.status == OperationStatus.running;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxWidth: 360, minWidth: 280),
      decoration: BoxDecoration(
        color: const Color(0xFF25252A),
        border: Border.all(color: isError ? const Color(0xFFC4314B) : const Color(0xFF404048)),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: InkWell(
        onTap: () => _openActivityPanel(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (isRunning) const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  if (!isRunning) Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                      size: 16, color: isError ? const Color(0xFFC4314B) : const Color(0xFF4EC9B0)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(op.label, style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12.5))),
                  if (isRunning)
                    IconButton(
                      icon: const Icon(Icons.close, size: 14, color: Color(0xFF888892)),
                      onPressed: () => ref.read(operationsProvider.notifier).cancel(op.id),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      tooltip: 'Cancel',
                    ),
                ],
              ),
              if (isRunning) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: op.progress, minHeight: 3),
                if (op.phase.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(op.phase, style: const TextStyle(color: Color(0xFF888892), fontSize: 11)),
                  ),
              ],
              if (isError && op.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(op.errorMessage!, style: const TextStyle(color: Color(0xFFC4314B), fontSize: 11)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openActivityPanel(BuildContext context) {
    showDialog(context: context, builder: (_) => const ActivityPanel());
  }
}
