import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class BranchCreateDialog extends ConsumerStatefulWidget {
  const BranchCreateDialog({required this.repo, super.key, this.at});
  final RepoLocation repo;
  final CommitSha? at;

  static Future<bool> show(BuildContext context, RepoLocation r,
      {CommitSha? at}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => BranchCreateDialog(repo: r, at: at),
    );
    return ok ?? false;
  }

  @override
  ConsumerState<BranchCreateDialog> createState() => _State();
}

class _State extends ConsumerState<BranchCreateDialog> {
  final _ctl = TextEditingController();
  bool _checkout = true;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AppDialog(
      title: 'New branch',
      subtitle: widget.at != null ? 'From ${widget.at!.short()}' : null,
      width: 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctl,
            autofocus: true,
            style: TextStyle(color: palette.fg0, fontSize: 13),
            decoration:
                appInputDecoration(context, label: 'Branch name'),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _checkout,
                onChanged: (v) => setState(() => _checkout = v ?? true),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                'Switch to this branch',
                style: TextStyle(color: palette.fg1, fontSize: 12.5),
              ),
            ],
          ),
        ],
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton.primary(
          label: 'Create',
          onPressed: _create,
        ),
      ],
    );
  }

  Future<void> _create() async {
    if (_ctl.text.trim().isEmpty) return;
    final result = await ref.read(gitActionsControllerProvider).createBranch(
          context,
          widget.repo,
          _ctl.text.trim(),
          at: widget.at,
          checkout: _checkout,
        );
    if (mounted) {
      Navigator.pop(context, result.outcome == ActionOutcome.success);
    }
  }
}
