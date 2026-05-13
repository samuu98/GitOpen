import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_palette.dart';

class KeyCombinationCapture extends StatefulWidget {
  final LogicalKeySet? initial;
  final void Function(LogicalKeySet) onCaptured;
  final VoidCallback onCancel;
  const KeyCombinationCapture({
    super.key, this.initial, required this.onCaptured, required this.onCancel,
  });

  @override
  State<KeyCombinationCapture> createState() => _State();
}

class _State extends State<KeyCombinationCapture> {
  final _focusNode = FocusNode();
  LogicalKeySet? _captured;
  String? _error;

  @override
  void initState() {
    super.initState();
    _captured = widget.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool _isModifier(LogicalKeyboardKey k) {
    return k == LogicalKeyboardKey.controlLeft || k == LogicalKeyboardKey.controlRight ||
           k == LogicalKeyboardKey.shiftLeft || k == LogicalKeyboardKey.shiftRight ||
           k == LogicalKeyboardKey.altLeft || k == LogicalKeyboardKey.altRight ||
           k == LogicalKeyboardKey.metaLeft || k == LogicalKeyboardKey.metaRight;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final nonModifier = pressed.where((k) => !_isModifier(k)).toList();
    if (nonModifier.isEmpty) {
      setState(() => _error = 'Need at least one non-modifier key.');
      return KeyEventResult.handled;
    }
    setState(() {
      _captured = LogicalKeySet.fromSet(pressed);
      _error = null;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return AlertDialog(
      title: const Text('Press a key combination'),
      content: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        autofocus: true,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: p.bg2, borderRadius: BorderRadius.circular(6)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_describe(_captured), style: TextStyle(color: p.fg0, fontSize: 16, fontFamily: 'monospace')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: p.accentErr, fontSize: 12)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _captured == null ? null : () => widget.onCaptured(_captured!),
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _describe(LogicalKeySet? set) {
    if (set == null) return '(press keys...)';
    return set.keys.map((k) => k.keyLabel.isNotEmpty ? k.keyLabel : k.debugName ?? '?').join(' + ');
  }
}
