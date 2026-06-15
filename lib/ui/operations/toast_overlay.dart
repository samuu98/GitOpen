import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/operations/activity_panel.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

// Both success and failure toasts auto-fade after this window.
const _autoDismiss = Duration(seconds: 10);

class ToastOverlay extends ConsumerStatefulWidget {
  const ToastOverlay({super.key});

  @override
  ConsumerState<ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends ConsumerState<ToastOverlay> {
  // Operation ids the user explicitly dismissed via the X button.
  final Set<String> _dismissed = {};

  // Drives a periodic rebuild so finished toasts disappear when their
  // 10-second window elapses (operationsProvider only fires on state changes,
  // not on time passing).
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ops = ref.watch(operationsProvider);
    final now = DateTime.now();
    final visible = ops
        .where((o) {
          if (_dismissed.contains(o.id)) return false;
          if (o.status == OperationStatus.running ||
              o.status == OperationStatus.pending) {
            return true;
          }
          if (o.finishedAt == null) return false;
          return now.difference(o.finishedAt!) < _autoDismiss;
        })
        .take(3)
        .toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return Positioned(
      right: 12,
      bottom: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final op in visible)
            _ToastItem(
              op: op,
              onDismiss: () => setState(() => _dismissed.add(op.id)),
            ),
        ],
      ),
    );
  }
}

class _ToastItem extends ConsumerWidget {
  const _ToastItem({required this.op, required this.onDismiss});
  final RunningOperation op;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final isError = op.status == OperationStatus.failed;
    final isRunning = op.status == OperationStatus.running;
    return Container(
      margin: EdgeInsets.only(top: spacing.sm),
      constraints: const BoxConstraints(maxWidth: 360, minWidth: 280),
      decoration: BoxDecoration(
        color: palette.bg2,
        border: Border.all(
          color: isError ? palette.accentErr : palette.borderStrong,
        ),
        borderRadius: radii.panelRadius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _openActivityPanel(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (isRunning)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (!isRunning)
                    Icon(
                      isError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: 16,
                      color: isError
                          ? palette.accentErr
                          : palette.accentCurrent,
                    ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      op.label,
                      style: TextStyle(color: palette.fg0, fontSize: 12.5),
                    ),
                  ),
                  if (isRunning)
                    _TinyIconButton(
                      icon: Icons.stop_circle_outlined,
                      tooltip: 'Cancel',
                      color: palette.fg2,
                      onTap: () =>
                          ref.read(operationsProvider.notifier).cancel(op.id),
                    ),
                  _TinyIconButton(
                    icon: Icons.close,
                    tooltip: 'Dismiss',
                    color: palette.fg2,
                    onTap: onDismiss,
                  ),
                ],
              ),
              if (isRunning) ...[
                SizedBox(height: spacing.xs),
                LinearProgressIndicator(value: op.progress, minHeight: 3),
                if (op.phase.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: spacing.xxs),
                    child: Text(
                      op.phase,
                      style: TextStyle(color: palette.fg2, fontSize: 11),
                    ),
                  ),
              ],
              if (isError && op.errorMessage != null)
                Padding(
                  padding: EdgeInsets.only(top: spacing.xxs),
                  child: Text(
                    op.errorMessage!,
                    style: TextStyle(color: palette.accentErr, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openActivityPanel(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const ActivityPanel(),
      ),
    );
  }
}

class _TinyIconButton extends StatefulWidget {
  const _TinyIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_TinyIconButton> createState() => _TinyIconButtonState();
}

class _TinyIconButtonState extends State<_TinyIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final radii = AppRadii.of(context);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: _hover ? palette.bg4 : Colors.transparent,
              borderRadius: radii.controlRadius,
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _hover ? palette.fg0 : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
