import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/git/auth_failure_classifier.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/account_switcher_dialog.dart';

/// Bridges the pure [AuthPrompt] to the account-switcher dialog. Captures the
/// [BuildContext] for the duration of one action. Shared by the git and LFS
/// action controllers.
class DialogAuthPrompt implements AuthPrompt {
  DialogAuthPrompt(this._context, this._ref);
  final BuildContext _context;
  final Ref _ref;

  @override
  Future<AuthProfile?> forAccount(
    RepoLocation repo,
    AuthFailureReason reason,
  ) async {
    final host =
        await _ref.read(authResolverProvider).hostFromRepo(repo, 'origin') ??
        'github.com';
    if (!_context.mounted) return null;
    final chosen = await AccountSwitcherDialog.show(
      _context,
      host: host,
      contextMessage: switch (reason) {
        AuthFailureReason.wrongAccount =>
          'Git returned "repository not found" — the active account likely '
              'cannot see this repo.',
        AuthFailureReason.authRequired => 'The active credential was rejected.',
      },
    );
    if (chosen == null) return null;
    await _ref
        .read(appSettingsProvider.notifier)
        .setAuthBinding(repo.id.value, chosen.id);
    return chosen;
  }
}

/// Bridges the pure [ProgressSink] to the operations notifier.
class OperationsProgressSink implements ProgressSink {
  OperationsProgressSink(this._ref);
  final Ref _ref;

  OperationsNotifier get _ops => _ref.read(operationsProvider.notifier);

  @override
  String start(OpKind kind, String label, {RepoLocation? repo}) =>
      _ops.start(kind, label, repo: repo);

  @override
  void progress(String id, double? fraction, String phase) =>
      _ops.updateProgress(id, fraction, phase);

  @override
  void success(String id) => _ops.finishSuccess(id);

  @override
  void failure(String id, String message) => _ops.finishFailure(id, message);
}
