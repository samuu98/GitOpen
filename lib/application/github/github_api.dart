import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/github/github_models.dart';

/// Why a GitHub API call failed, so the panel can render the right inline
/// state (sign-in CTA, rate-limit notice, retry, ...).
enum GitHubApiErrorKind { auth, rateLimit, network, notFound }

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
}

/// The token usable for the GitHub REST API carried by [spec], or null when
/// the credential has no API-compatible token (ssh, basic, system default).
String? githubTokenOf(AuthSpec? spec) => switch (spec) {
  AuthGitHubOauth(:final accessToken) => accessToken,
  AuthHttpsPat(:final token) => token,
  _ => null,
};
