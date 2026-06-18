import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/commit_request.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/author_avatar.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class CommitCompose extends ConsumerStatefulWidget {
  const CommitCompose({required this.repo, super.key});
  final RepoLocation repo;
  @override
  ConsumerState<CommitCompose> createState() => _CommitComposeState();
}

/// Lookup of the effective author identity for the active repo — driving
/// the small "Committing as …" header in the compose panel.
final _composeIdentityProvider =
    FutureProvider.autoDispose.family<({String? name, String? email}),
            RepoLocation>(
  (ref, repo) => ref.read(gitIdentityServiceProvider).readEffective(repo),
);

class _CommitComposeState extends ConsumerState<CommitCompose> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  bool _amend = false;
  bool _signOff = false;
  bool _sign = false;
  bool _busy = false;
  int _lastTrigger = 0;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = ref.read(appSettingsProvider);
      setState(() {
        if (s.commitSignoffDefault) _signOff = true;
        if (s.gpgSignByDefault) _sign = true;
      });
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // React to keyboard shortcut (Ctrl+Enter) via triggerCommitProvider.
    final triggerCount = ref.watch(triggerCommitProvider);
    if (triggerCount != _lastTrigger) {
      _lastTrigger = triggerCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_commit());
      });
    }

    final palette = AppPalette.of(context);
    final identityAsync = ref.watch(_composeIdentityProvider(widget.repo));
    final (subject, _) = _splitMessage(_ctl.text);
    final canCommit =
        !_busy && (_ctl.text.trim().isNotEmpty || _amend);

    return Container(
      decoration: BoxDecoration(
        color: palette.bg2,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IdentityStrip(identity: identityAsync.value, amend: _amend),
          const SizedBox(height: 8),
          _MessageField(
            controller: _ctl,
            focusNode: _focus,
            onSubmit: canCommit ? _commit : null,
            palette: palette,
          ),
          const SizedBox(height: 6),
          _SubjectMeter(subject: subject, palette: palette),
          const SizedBox(height: 10),
          Row(
            children: [
              _OptionPill(
                icon: Icons.history_edu,
                label: 'Amend',
                active: _amend,
                onTap: () => setState(() => _amend = !_amend),
              ),
              const SizedBox(width: 6),
              _OptionPill(
                icon: Icons.draw_outlined,
                label: 'Sign-off',
                active: _signOff,
                onTap: () => setState(() => _signOff = !_signOff),
              ),
              const SizedBox(width: 6),
              _OptionPill(
                icon: Icons.verified_user_outlined,
                label: 'Sign (GPG)',
                active: _sign,
                onTap: () => setState(() => _sign = !_sign),
              ),
              const Spacer(),
              _CommitButton(
                busy: _busy,
                enabled: canCommit,
                amend: _amend,
                onTap: _commit,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _commit() async {
    if (!mounted || _busy) return;
    if (_ctl.text.trim().isEmpty && !_amend) return;
    setState(() => _busy = true);
    final ops = ref.read(operationsProvider.notifier);
    final opId = ops.start(
      OpKind.commit,
      _amend ? 'Amend commit' : 'Commit',
      repo: widget.repo,
    );
    final res = await ref.read(gitWriteOperationsProvider).commit(
          widget.repo,
          CommitRequest(
            message: _ctl.text.trim(),
            amend: _amend,
            signOff: _signOff,
            sign: _sign,
          ),
        );
    // Report through the shared operations/toast system, like fetch/pull/push
    // — the notifier outlives this widget, so finish the op even if unmounted.
    if (res is GitSuccess) {
      ops.finishSuccess(opId);
    } else if (res is GitFailure<CommitSha>) {
      ops.finishFailure(opId, res.message);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (res is GitSuccess) {
      _ctl.clear();
      setState(() {
        _amend = false;
        _signOff = false;
        _sign = false;
      });
      ref.invalidate(gitReadOperationsProvider);
    }
  }
}

(String subject, String body) _splitMessage(String message) {
  final trimmed = message.trimRight();
  final nl = trimmed.indexOf('\n');
  if (nl < 0) return (trimmed, '');
  return (trimmed.substring(0, nl), trimmed.substring(nl + 1));
}

class _IdentityStrip extends StatelessWidget {
  const _IdentityStrip({required this.identity, required this.amend});
  final ({String? name, String? email})? identity;
  final bool amend;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final name = identity?.name ?? '…';
    final email = identity?.email ?? '';
    return Row(
      children: [
        AuthorAvatar(name: name, email: email),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style:
                  TextStyle(color: palette.fg2, fontSize: 11.5, height: 1.2),
              children: [
                const TextSpan(text: 'Committing as '),
                TextSpan(
                  text: name,
                  style: TextStyle(
                      color: palette.fg0, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        if (amend)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: palette.accentWarn.withValues(alpha: 0.18),
              border: Border.all(color: palette.accentWarn),
              borderRadius: AppRadii.of(context).controlRadius,
            ),
            child: Text(
              'AMEND',
              style: TextStyle(
                color: palette.accentWarn,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
      ],
    );
  }
}

class _MessageField extends StatefulWidget {
  const _MessageField({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.palette,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onSubmit;
  final AppPalette palette;

  @override
  State<_MessageField> createState() => _MessageFieldState();
}

class _MessageFieldState extends State<_MessageField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border.all(
            color: _focused ? palette.accentCurrent : palette.border,
            width: _focused ? 1.2 : 1),
        borderRadius: AppRadii.of(context).controlRadius,
      ),
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter, control: true):
              _SubmitIntent(),
        },
        child: Actions(
          actions: {
            _SubmitIntent: CallbackAction<_SubmitIntent>(
              onInvoke: (_) {
                widget.onSubmit?.call();
                return null;
              },
            ),
          },
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            minLines: 3,
            maxLines: 6,
            style: TextStyle(
              color: palette.fg0,
              fontSize: 12.5,
              fontFamily: 'monospace',
              height: 1.45,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              hintText:
                  'Summary\n\nDetails (optional)\n\n⌘/Ctrl + Enter to commit',
              hintStyle: TextStyle(
                color: palette.fg3,
                fontSize: 12.5,
                fontFamily: 'monospace',
                height: 1.45,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

class _SubjectMeter extends StatelessWidget {
  const _SubjectMeter({required this.subject, required this.palette});
  final String subject;
  final AppPalette palette;

  static const _good = 50;
  static const _max = 72;

  @override
  Widget build(BuildContext context) {
    final len = subject.length;
    final Color barColor;
    final String hint;
    if (len == 0) {
      barColor = palette.border;
      hint = 'Keep the subject line under $_good characters.';
    } else if (len <= _good) {
      barColor = palette.accentCurrent;
      hint = '$len / $_good';
    } else if (len <= _max) {
      barColor = palette.accentTag;
      hint = '$len chars — getting long ($_good recommended).';
    } else {
      barColor = palette.accentErr;
      hint = '$len chars — over $_max.';
    }
    final progress = (len / _max).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: palette.bg3,
                color: barColor,
                minHeight: 3,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          hint,
          style: TextStyle(color: palette.fg3, fontSize: 10.5),
        ),
      ],
    );
  }
}

class _OptionPill extends StatefulWidget {
  const _OptionPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_OptionPill> createState() => _OptionPillState();
}

class _OptionPillState extends State<_OptionPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final active = widget.active;
    final fg = active ? palette.fg0 : palette.fg1;
    return Tooltip(
      message: active ? '${widget.label} — on' : '${widget.label} — off',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: active
                  ? palette.bgAccent.withValues(alpha: 0.32)
                  : (_hover ? palette.bg3 : palette.bg2),
              border: Border.all(
                color: active ? palette.bgAccent : palette.border,
              ),
              borderRadius: AppRadii.of(context).controlRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon,
                    size: 12,
                    color: active ? palette.accentCurrent : palette.fg2),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 11.5,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommitButton extends StatelessWidget {
  const _CommitButton({
    required this.busy,
    required this.enabled,
    required this.amend,
    required this.onTap,
  });
  final bool busy;
  final bool enabled;
  final bool amend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = amend ? 'Amend' : 'Commit';
    if (busy) {
      // Show a busy version that still uses AppButton chrome.
      return const SizedBox(
        height: 30,
        width: 100,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return AppButton.primary(
      icon: amend ? Icons.history_edu : Icons.check,
      label: label,
      onPressed: enabled ? onTap : null,
    );
  }
}
