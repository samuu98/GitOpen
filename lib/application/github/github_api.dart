import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/github/github_models.dart';

/// Why a GitHub API call failed, so the panel can render the right inline
/// state (sign-in CTA, rate-limit notice, retry, ...).
enum GitHubApiErrorKind {
  auth,
  rateLimit,
  network,
  notFound,
  validation,
  conflict,
  mergeBlocked,
}

/// Typed failure surfaced by [GitHubApi] implementations. `toString` is safe
/// to show to the user as-is.
final class GitHubApiException implements Exception {
  const GitHubApiException(this.kind, this.message);
  final GitHubApiErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Read-only GitHub data the panel needs. Implementations throw
/// [GitHubApiException] (never transport exceptions) on failure.
abstract interface class GitHubApi {
  /// Open pull requests of [slug], most recently updated first.
  Future<List<PullRequestInfo>> listPullRequests(
    RepoSlug slug, {
    required String token,
  });

  /// Recent Actions workflow runs of [slug]; [branch] filters to runs whose
  /// head is that branch.
  Future<List<WorkflowRunInfo>> listWorkflowRuns(
    RepoSlug slug, {
    required String token,
    String? branch,
  });

  /// Check-run summary for the commit [headSha] (a PR's head).
  Future<CheckSummary> prChecks(
    RepoSlug slug,
    String headSha, {
    required String token,
  });

  Future<PullRequestDetail> getPullRequest(
    RepoSlug slug,
    int number, {
    required String token,
  });

  Future<List<PullRequestFile>> listPullRequestFiles(
    RepoSlug slug,
    int number, {
    required String token,
  });

  Future<List<PullRequestReview>> listPullRequestReviews(
    RepoSlug slug,
    int number, {
    required String token,
  });

  Future<List<PullRequestComment>> listPullRequestReviewComments(
    RepoSlug slug,
    int number, {
    required String token,
  });

  Future<List<IssueCommentInfo>> listPullRequestIssueComments(
    RepoSlug slug,
    int number, {
    required String token,
  });

  Future<PullRequestDetail> createPullRequest(
    RepoSlug slug,
    CreatePullRequestRequest request, {
    required String token,
  });

  Future<PullRequestDetail> updatePullRequest(
    RepoSlug slug,
    int number,
    UpdatePullRequestRequest request, {
    required String token,
  });

  Future<PullRequestDetail> markPullRequestReadyForReview(
    RepoSlug slug,
    int number, {
    required String token,
  });

  Future<void> mergePullRequest(
    RepoSlug slug,
    int number,
    MergePullRequestRequest request, {
    required String token,
  });

  Future<IssueCommentInfo> createIssueComment(
    RepoSlug slug,
    int number,
    String body, {
    required String token,
  });

  Future<PullRequestReview> createReview(
    RepoSlug slug,
    int number,
    SubmitReviewRequest request, {
    required String token,
  });

  Future<PullRequestComment> createReviewCommentReply(
    RepoSlug slug,
    int number,
    int commentId,
    String body, {
    required String token,
  });
}

/// The token usable for the GitHub REST API carried by [spec], or null when
/// the credential has no API-compatible token (ssh, basic, system default).
String? githubTokenOf(AuthSpec? spec) => switch (spec) {
  AuthGitHubOauth(:final accessToken) => accessToken,
  AuthHttpsPat(:final token) => token,
  _ => null,
};
