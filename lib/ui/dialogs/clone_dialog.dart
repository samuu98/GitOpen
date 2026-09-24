import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/common/app_panel_state.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/welcome/workspace_ready.dart';

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
  bool _cancelled = false;
  String? _operationId;
  StreamSubscription<GitProgress>? _subscription;
  String? _error;
  String? _loadError;
  RepoLocation? _readyRepo;

  @override
  void dispose() {
    final sub = _subscription;
    if (sub != null) unawaited(sub.cancel());
    _urlCtl.dispose();
    _destCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PopScope(
      canPop: !_busy,
      child: AppDialog(
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _destCtl,
                    style: TextStyle(color: palette.fg0, fontSize: 13),
                    decoration: appInputDecoration(
                      context,
                      label: 'Destination',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AppIconButton(
                  icon: Icons.folder_open,
                  tooltip: 'Browse…',
                  onPressed: _busy ? null : _pickDest,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Checkbox(
                  value: _openAfter,
                  onChanged: (v) => setState(() => _openAfter = v ?? true),
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  'Open after clone',
                  style: TextStyle(color: palette.fg1, fontSize: 12.5),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 14, color: palette.accentErr),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: palette.accentErr,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_loadError != null) ...[
              const SizedBox(height: 12),
              AppErrorState(
                message: 'Could not load repository',
                detail: _loadError,
                onRetry: _retryReady,
              ),
            ],
          ],
        ),
        actions: [
          AppButton.secondary(
            label: 'Cancel',
            onPressed: _cancel,
          ),
          AppButton.primary(
            label: _error == null ? 'Clone' : 'Retry',
            onPressed: _busy || _loadError != null ? null : _clone,
          ),
        ],
      ),
    );
  }

  Future<void> _cancel() async {
    if (!_busy) {
      Navigator.pop(context);
      return;
    }
    if (_cancelled) return;
    _cancelled = true;
    final id = _operationId;
    if (id == null) {
      _close();
    } else {
      ref.read(operationsProvider.notifier).cancel(id);
    }
  }

  void _close() {
    if (!mounted) return;
    setState(() => _busy = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _pickDest() async {
    final dir = await getDirectoryPath();
    if (dir != null && mounted) _destCtl.text = dir;
  }

  Future<void> _clone() async {
    if (_busy) return;
    if (_urlCtl.text.isEmpty || _destCtl.text.isEmpty) return;
    final url = _urlCtl.text.trim();
    final dest = _destCtl.text.trim();
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _loadError = null;
      _readyRepo = null;
    });
    final ops = ref.read(operationsProvider.notifier);
    final done = Completer<void>();
    final id = ops.start(
      OpKind.clone,
      'Cloning $url',
      onCancel: () {
        _cancelled = true;
        final sub = _subscription;
        if (sub == null) {
          if (!done.isCompleted) done.complete();
        } else {
          unawaited(sub.cancel());
          if (!done.isCompleted) done.complete();
        }
      },
    );
    _operationId = id;
    final write = ref.read(gitWriteOperationsProvider);
    final errorText = ref.read(gitErrorTextProvider);
    var cloneFinished = false;
    try {
      final host = Uri.tryParse(url)?.host ?? '';
      final profiles = host.isEmpty
          ? null
          : await ref.read(authProfileStoreProvider).forHost(host);
      if (!_cancelled) {
        _subscription = write
            .clone(
              url,
              dest,
              auth: profiles?.length == 1 ? profiles!.single.spec : null,
            )
            .listen(
              (ev) => ops.updateProgress(id, ev.fraction, ev.phase),
              onError: (Object e, StackTrace s) {
                if (!done.isCompleted) done.completeError(e, s);
              },
              onDone: () {
                if (!done.isCompleted) done.complete();
              },
              cancelOnError: true,
            );
      }
      await done.future;
      if (_cancelled) {
        _close();
        return;
      }
      cloneFinished = true;
      if (_openAfter && mounted) {
        final manager = ref.read(workspaceManagerProvider.notifier);
        final active = ref.read(activeWorkspaceIdProvider.notifier);
        final ws = await manager.open(dest);
        if (!mounted || _cancelled) {
          if (_cancelled) _close();
          return;
        }
        _readyRepo = ws.location;
        await ref.read(workspaceReadyProvider(ws.location).future);
        if (!mounted || _cancelled) {
          if (_cancelled) _close();
          return;
        }
        active.state = ws.location.id;
      }
      ops.finishSuccess(id);
      _close();
    } on Object catch (e) {
      final message = errorText(e);
      if (!_cancelled) ops.finishFailure(id, message);
      // Inline error + retry: the dialog stays open with the inputs intact
      // so the user can fix the URL/destination and try again.
      if (mounted) {
        setState(() {
          _busy = false;
          if (cloneFinished && _readyRepo != null) {
            _loadError = message;
          } else {
            _error = message;
          }
        });
      }
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      _operationId = null;
    }
  }

  Future<void> _retryReady() async {
    final repo = _readyRepo;
    if (_busy || repo == null) return;
    setState(() {
      _busy = true;
      _loadError = null;
    });
    try {
      await retryWorkspaceReady(
        ProviderScope.containerOf(context, listen: false),
        repo,
      );
      if (!mounted) return;
      ref.read(activeWorkspaceIdProvider.notifier).state = repo.id;
      _close();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _loadError = ref.read(gitErrorTextProvider)(error);
        });
      }
    }
  }
}
