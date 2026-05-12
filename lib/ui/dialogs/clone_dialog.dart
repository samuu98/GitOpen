import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';

class CloneDialog extends ConsumerStatefulWidget {
  const CloneDialog({super.key});
  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const CloneDialog());

  @override
  ConsumerState<CloneDialog> createState() => _State();
}

class _State extends ConsumerState<CloneDialog> {
  final _urlCtl = TextEditingController();
  final _destCtl = TextEditingController();
  bool _openAfter = true;
  bool _busy = false;

  @override
  void dispose() {
    _urlCtl.dispose();
    _destCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clone repository'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _urlCtl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Repository URL'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _destCtl,
                decoration: const InputDecoration(labelText: 'Destination'),
              ),
            ),
            IconButton(icon: const Icon(Icons.folder_open), onPressed: _pickDest),
          ]),
          Row(children: [
            Checkbox(
              value: _openAfter,
              onChanged: (v) => setState(() => _openAfter = v ?? true),
            ),
            const Text('Open after clone'),
          ]),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _clone,
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Clone'),
        ),
      ],
    );
  }

  Future<void> _pickDest() async {
    final dir = await getDirectoryPath();
    if (dir != null) _destCtl.text = dir;
  }

  Future<void> _clone() async {
    if (_urlCtl.text.isEmpty || _destCtl.text.isEmpty) return;
    final url = _urlCtl.text.trim();
    final dest = _destCtl.text.trim();
    setState(() => _busy = true);
    final ops = ref.read(operationsProvider.notifier);
    final id = ops.start(OpKind.clone, 'Cloning $url');
    final write = ref.read(gitWriteOperationsProvider);
    try {
      await for (final ev in write.clone(url, dest)) {
        ops.updateProgress(id, ev.fraction, ev.phase);
      }
      ops.finishSuccess(id);
      if (_openAfter && mounted) {
        final manager = ref.read(workspaceManagerProvider.notifier);
        final ws = await manager.open(dest);
        ref.read(activeWorkspaceIdProvider.notifier).state = ws.location.id;
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ops.finishFailure(id, e.toString());
      if (mounted) setState(() => _busy = false);
    }
  }
}
