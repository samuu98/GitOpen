import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/git/auth_failure_classifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// Interactive re-authentication, implemented by the UI (the account switcher).
///
/// Lets the pure `GitActionsService` ask the user to pick or add an account
/// mid-operation without depending on Flutter.
abstract interface class AuthPrompt { // ignore: one_member_abstracts
  /// After an auth / wrong-account failure on [repo], asks the user to choose
  /// or add an account. Implementations bind the chosen profile to the repo
  /// before returning it; returns `null` if the user cancelled (no retry).
  Future<AuthProfile?> forAccount(RepoLocation repo, AuthFailureReason reason);
}

/// Sink for an operation's lifecycle + progress, implemented over the
/// operations notifier (which drives the toast / activity-panel UI).
abstract interface class ProgressSink {
  /// Registers a new running operation and returns its id. [onCancel], when
  /// provided, is invoked if the user cancels the operation (network ops kill
  /// the git process); omit it for non-cancelable (local) operations.
  String start(
    OpKind kind,
    String label, {
    RepoLocation? repo,
    void Function()? onCancel,
  });

  /// Feeds progress for the operation [id] while it runs.
  void progress(String id, double? fraction, String phase);

  /// Marks the operation [id] complete (success).
  void success(String id);

  /// Marks the operation [id] complete (failure) with a [message].
  void failure(String id, String message);
}

/// Minimal logging port so application code logs without importing the
/// infrastructure logger directly (keeps the layering one-directional).
abstract interface class LoggerPort {
  /// Logs a debug/trace message.
  void d(String message);

  /// Logs an informational message.
  void i(String message);

  /// Logs a warning.
  void w(String message);
}
