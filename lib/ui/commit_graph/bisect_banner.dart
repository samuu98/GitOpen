import 'package:flutter/material.dart';
import 'package:gitopen/application/git/bisect_state.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

enum BisectAction { good, bad, skip, reset }

/// Persistent controls for the current bisect candidate or its result.
class BisectBanner extends StatefulWidget {
  const BisectBanner({
    required this.state,
    required this.onAction,
    required this.onSelect,
    super.key,
  });

  final BisectState state;
  final Future<String?> Function(BisectAction action) onAction;
  final void Function(CommitSha sha) onSelect;

  @override
  State<BisectBanner> createState() => _BisectBannerState();
}

class _BisectBannerState extends State<BisectBanner> {
  bool _busy = false;
  String? _error;

  Future<void> _run(BisectAction action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onAction(action);
    } on Object catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = widget.state;
    final found = state.firstBad;
    return Container(
      width: double.infinity,
      color: palette.accentWarn.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                found == null
                    ? 'Bisect candidate ${state.candidate.short()} — '
                          '${state.subject} · ${state.stepsLeft} steps left'
                    : 'First bad commit ${found.short()} — ${state.subject}',
                style: TextStyle(color: palette.fg0, fontSize: 12.5),
              ),
              if (_busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (found == null) ...[
                TextButton(
                  onPressed: _busy ? null : () => _run(BisectAction.good),
                  child: const Text('Good'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _run(BisectAction.bad),
                  child: const Text('Bad'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _run(BisectAction.skip),
                  child: const Text('Skip'),
                ),
              ] else
                TextButton(
                  onPressed: _busy ? null : () => widget.onSelect(found),
                  child: const Text('Select in graph'),
                ),
              TextButton(
                onPressed: _busy ? null : () => _run(BisectAction.reset),
                child: const Text('Reset'),
              ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: palette.accentErr, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
