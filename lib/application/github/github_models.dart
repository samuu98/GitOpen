import 'package:equatable/equatable.dart';

/// `owner/repo` pair identifying a GitHub repository.
typedef RepoSlug = ({String owner, String repo});

/// Aggregated state of a commit's check runs.
enum CheckState { none, pending, success, failure }

/// Counts of a commit's check runs by outcome. [state] folds them into the
/// single chip the PR list shows - any failure wins, then any pending.
final class CheckSummary extends Equatable {
  const CheckSummary({
    required this.total,
    required this.succeeded,
    required this.failed,
    required this.pending,
  });
  final int total;
  final int succeeded;
  final int failed;
  final int pending;

  CheckState get state => total == 0
      ? CheckState.none
      : failed > 0
          ? CheckState.failure
          : pending > 0
              ? CheckState.pending
              : CheckState.success;

  @override
  List<Object?> get props => [total, succeeded, failed, pending];
}

/// An open pull request, as listed by the GitHub REST API.
final class PullRequestInfo extends Equatable {
  const PullRequestInfo({
    required this.number,
    required this.title,
    required this.author,
    required this.isDraft,
    required this.headRef,
    required this.headSha,
    required this.htmlUrl,
    required this.updatedAt,
  });
  final int number;
  final String title;
  final String author;
  final bool isDraft;
  final String headRef;

  /// Sha of the PR's head commit - the ref used for PR check summaries.
  final String headSha;
  final String htmlUrl;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [
        number,
        title,
        author,
        isDraft,
        headRef,
        headSha,
        htmlUrl,
        updatedAt,
      ];
}

/// A GitHub Actions workflow run. [status] is the raw API value
/// (`queued`/`in_progress`/`completed`); [conclusion] is set only when
/// completed (`success`/`failure`/`cancelled`/...).
final class WorkflowRunInfo extends Equatable {
  const WorkflowRunInfo({
    required this.id,
    required this.name,
    required this.headBranch,
    required this.status,
    required this.htmlUrl,
    required this.createdAt,
    required this.updatedAt,
    this.conclusion,
  });
  final int id;
  final String name;
  final String headBranch;
  final String status;
  final String? conclusion;
  final String htmlUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCompleted => status == 'completed';
  Duration get duration => updatedAt.difference(createdAt);

  @override
  List<Object?> get props => [
        id,
        name,
        headBranch,
        status,
        conclusion,
        htmlUrl,
        createdAt,
        updatedAt,
      ];
}
