import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';
import '../theme/app_palette.dart';
import 'app_dialog.dart';

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
    final palette = AppPalette.of(context);
    return AppDialog(
      title: 'Clone repository',
      busy: _busy,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _urlCtl,
            autofocus: true,
            style: TextStyle(color: palette.fg0, fontSize: 13),
            decoration: appInputDecoration(
              context,
              label: 'Repository URL',
              hint: 'https://github.com/user/repo.git',
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _destCtl,
                style: TextStyle(color: palette.fg0, fontSize: 13),
                decoration: appInputDecoration(context, label: 'Destination'),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.folder_open, color: palette.fg1, size: 18),
              tooltip: 'Browse…',
              onPressed: _pickDest,
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Checkbox(
              value: _openAfter,
              onChanged: (v) => setState(() => _openAfter = v ?? true),
              visualDensity: VisualDensity.compact,
            ),
            Text(
              'Open after clone',
              style: TextStyle(color: palette.fg1, fontSize: 12.5),
            ),
          ]),
        ],
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        AppButton.primary(
          label: 'Clone',
          onPressed: _busy ? null : _clone,
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
