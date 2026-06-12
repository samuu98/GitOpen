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

enum PullRequestMergeMethod { merge, squash, rebase }

final class PullRequestDetail extends Equatable {
  const PullRequestDetail({
    required this.number,
    required this.nodeId,
    required this.title,
    required this.body,
    required this.author,
    required this.state,
    required this.isDraft,
    required this.mergeable,
    required this.mergeStateStatus,
    required this.baseRef,
    required this.headRef,
    required this.headSha,
    required this.htmlUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final int number;
  final String nodeId;
  final String title;
  final String body;
  final String author;
  final String state;
  final bool isDraft;
  final bool? mergeable;
  final String mergeStateStatus;
  final String baseRef;
  final String headRef;
  final String headSha;
  final String htmlUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOpen => state == 'open';

  @override
  List<Object?> get props => [
    number,
    nodeId,
    title,
    body,
    author,
    state,
    isDraft,
    mergeable,
    mergeStateStatus,
    baseRef,
    headRef,
    headSha,
    htmlUrl,
    createdAt,
    updatedAt,
  ];
}

final class PullRequestFile extends Equatable {
  const PullRequestFile({
    required this.filename,
    required this.status,
    required this.additions,
    required this.deletions,
    required this.changes,
    required this.patch,
  });

  final String filename;
  final String status;
  final int additions;
  final int deletions;
  final int changes;
  final String patch;

  @override
  List<Object?> get props => [
    filename,
    status,
    additions,
    deletions,
    changes,
    patch,
  ];
}

final class PullRequestReview extends Equatable {
  const PullRequestReview({
    required this.id,
    required this.user,
    required this.state,
    required this.body,
    required this.submittedAt,
    required this.htmlUrl,
  });

  final int id;
  final String user;
  final String state;
  final String body;
  final DateTime? submittedAt;
  final String htmlUrl;

  @override
  List<Object?> get props => [id, user, state, body, submittedAt, htmlUrl];
}

final class PullRequestComment extends Equatable {
  const PullRequestComment({
    required this.id,
    required this.user,
    required this.body,
    required this.path,
    required this.side,
    required this.line,
    required this.position,
    required this.inReplyToId,
    required this.createdAt,
    required this.updatedAt,
    required this.htmlUrl,
  });

  final int id;
  final String user;
  final String body;
  final String path;
  final String side;
  final int? line;
  final int? position;
  final int? inReplyToId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String htmlUrl;

  @override
  List<Object?> get props => [
    id,
    user,
    body,
    path,
    side,
    line,
    position,
    inReplyToId,
    createdAt,
    updatedAt,
    htmlUrl,
  ];
}

final class IssueCommentInfo extends Equatable {
  const IssueCommentInfo({
    required this.id,
    required this.user,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.htmlUrl,
  });

  final int id;
  final String user;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String htmlUrl;

  @override
  List<Object?> get props => [id, user, body, createdAt, updatedAt, htmlUrl];
}

final class CreatePullRequestRequest extends Equatable {
  const CreatePullRequestRequest({
    required this.title,
    required this.body,
    required this.head,
    required this.base,
    required this.draft,
  });

  final String title;
  final String body;
  final String head;
  final String base;
  final bool draft;

  Map<String, Object?> toJson() => {
    'title': title,
    'body': body,
    'head': head,
    'base': base,
    'draft': draft,
  };

  @override
  List<Object?> get props => [title, body, head, base, draft];
}

final class UpdatePullRequestRequest extends Equatable {
  const UpdatePullRequestRequest({
    this.title,
    this.body,
    this.state,
    this.base,
    this.maintainerCanModify,
  });

  final String? title;
  final String? body;
  final String? state;
  final String? base;
  final bool? maintainerCanModify;

  Map<String, Object?> toJson() => {
    if (title != null) 'title': title,
    if (body != null) 'body': body,
    if (state != null) 'state': state,
    if (base != null) 'base': base,
    if (maintainerCanModify != null)
      'maintainer_can_modify': maintainerCanModify,
  };

  @override
  List<Object?> get props => [title, body, state, base, maintainerCanModify];
}

final class DraftReviewComment extends Equatable {
  const DraftReviewComment({
    required this.path,
    required this.body,
    required this.line,
    required this.side,
  });

  final String path;
  final String body;
  final int line;
  final String side;

  Map<String, Object?> toJson() => {
    'path': path,
    'body': body,
    'line': line,
    'side': side,
  };

  @override
  List<Object?> get props => [path, body, line, side];
}

final class SubmitReviewRequest extends Equatable {
  const SubmitReviewRequest({
    required this.event,
    required this.body,
    required this.comments,
  });

  final String event;
  final String body;
  final List<DraftReviewComment> comments;

  Map<String, Object?> toJson() => {
    'event': event,
    'body': body,
    if (comments.isNotEmpty) 'comments': [for (final c in comments) c.toJson()],
  };

  @override
  List<Object?> get props => [event, body, comments];
}

final class MergePullRequestRequest extends Equatable {
  const MergePullRequestRequest({
    required this.method,
    this.commitTitle,
    this.commitMessage,
  });

  final PullRequestMergeMethod method;
  final String? commitTitle;
  final String? commitMessage;

  Map<String, Object?> toJson() => {
    'merge_method': method.name,
    if (commitTitle != null && commitTitle!.isNotEmpty)
      'commit_title': commitTitle,
    if (commitMessage != null && commitMessage!.isNotEmpty)
      'commit_message': commitMessage,
  };

  @override
  List<Object?> get props => [method, commitTitle, commitMessage];
}
