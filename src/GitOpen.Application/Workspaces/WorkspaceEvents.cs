using GitOpen.Domain.Repositories;

namespace GitOpen.Application.Workspaces;

public sealed record WorkspaceOpened(RepoLocation Location);
public sealed record WorkspaceClosed(RepoId Id);
public sealed record WorkspacesReordered(IReadOnlyList<RepoId> NewOrder);
