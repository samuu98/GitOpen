import 'dart:io';
import 'package:equatable/equatable.dart';
import '../../domain/repositories/repo_location.dart';

enum OpKind { fetch, pull, push, clone, commit, merge, cherryPick, stash, branch, reset, other }
enum OperationStatus { pending, running, success, failed, cancelled }

class RunningOperation extends Equatable {
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
  final Process? process;
  final String? errorMessage;

  const RunningOperation({
    required this.id,
    required this.kind,
    required this.label,
    this.repo,
    this.status = OperationStatus.pending,
    this.progress,
    this.phase = '',
    this.stderrTail = const [],
    required this.startedAt,
    this.finishedAt,
    this.process,
    this.errorMessage,
  });

  RunningOperation copyWith({
    OperationStatus? status,
    double? progress,
    String? phase,
    List<String>? stderrTail,
    DateTime? finishedAt,
    Process? process,
    String? errorMessage,
  }) {
    return RunningOperation(
      id: id, kind: kind, label: label, repo: repo, startedAt: startedAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      phase: phase ?? this.phase,
      stderrTail: stderrTail ?? this.stderrTail,
      finishedAt: finishedAt ?? this.finishedAt,
      process: process ?? this.process,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [id, status, progress, phase, finishedAt];
}
