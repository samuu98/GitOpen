import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Full-screen modal shown while a git operation runs. Absorbs all input so
/// the user can't navigate or start another action mid-operation. Shows a
/// Cancel button when a cancelable (network) operation is running.
class BlockingOverlay extends ConsumerWidget {
  const BlockingOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(busyProvider);
    if (!busy.isBusy) return const SizedBox.shrink();
    final palette = AppPalette.of(context);

    // Cancel comes from a running network op that registered an onCancel.
    final cancelable = ref.watch(operationsProvider).firstWhereOrNull(
          (o) => o.status == OperationStatus.running && o.onCancel != null,
        );
    final label = busy.label ?? cancelable?.label ?? 'Working…';

    return Positioned.fill(
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Color(0x66000000)),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: palette.bg2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    label,
                    style: TextStyle(color: palette.fg0, fontSize: 13),
                  ),
                  if (cancelable != null) ...[
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () => ref
                          .read(operationsProvider.notifier)
                          .cancel(cancelable.id),
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
