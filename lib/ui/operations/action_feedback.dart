import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';

/// The one surface every action outside a dialog reports to.
///
/// Policy (audit F20/F21): network and long operations already own a progress
/// toast and end on a success toast; short local writes get **no** success
/// toast — the refreshed view is the feedback — and every failure outside a
/// dialog shows git's own message here. Errors raised inside an open dialog
/// stay inline in that dialog.
final actionFeedbackProvider = Provider<ActionFeedback>(ActionFeedback.new);

class ActionFeedback {
  ActionFeedback(this._ref);
  final Ref _ref;

  /// Reports a failed action. [retry] adds a Retry button to the toast — used
  /// for a refresh that failed after the command itself succeeded.
  void showActionFailure(
    String message, {
    String label = 'Action failed',
    void Function()? retry,
  }) {
    final ops = _ref.read(operationsProvider.notifier);
    final id = ops.start(OpKind.other, label, onRetry: retry);
    ops.finishFailure(id, message, onRetry: retry);
  }

  /// Confirms a completed action. Reserve it for work the refreshed view does
  /// not already make obvious.
  void showActionSuccess(String message) {
    final ops = _ref.read(operationsProvider.notifier);
    ops.finishSuccess(ops.start(OpKind.other, message));
  }
}
