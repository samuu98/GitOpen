import 'package:equatable/equatable.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

enum OpKind {
  fetch,
  pull,
  push,
  clone,
  commit,
  merge,
  cherryPick,
  stash,
  branch,
  reset,
  other,
}

enum OperationStatus { pending, running, success, failed, cancelled }

class RunningOperation extends Equatable {

  const RunningOperation({
    required this.id,
    required this.kind,
    required this.label,
    required this.startedAt, this.repo,
    this.status = OperationStatus.pending,
    this.progress,
    this.phase = '',
    this.stderrTail = const [],
    this.finishedAt,
    this.onCancel,
    this.errorMessage,
  });
  final String id;
  final OpKind kind;
  final String label;
  final RepoLocation? repo;
  final OperationStatus status;
  final double? progress;
  final String phase;
  final List<String> stderrTail;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// Aborts the underlying work when the user cancels the operation (e.g.
  /// kills the spawned process). Null for operations that can't be cancelled.
  final void Function()? onCancel;
  final String? errorMessage;

  RunningOperation copyWith({
    OperationStatus? status,
    double? progress,
    String? phase,
    List<String>? stderrTail,
    DateTime? finishedAt,
    void Function()? onCancel,
    String? errorMessage,
  }) {
    return RunningOperation(
      id: id, kind: kind, label: label, repo: repo, startedAt: startedAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      phase: phase ?? this.phase,
      stderrTail: stderrTail ?? this.stderrTail,
      finishedAt: finishedAt ?? this.finishedAt,
      onCancel: onCancel ?? this.onCancel,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [id, status, progress, phase, finishedAt];
}
