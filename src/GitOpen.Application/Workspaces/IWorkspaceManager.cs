using GitOpen.Domain.Repositories;

namespace GitOpen.Application.Workspaces;

public interface IWorkspaceManager
{
    IReadOnlyList<Workspace> All { get; }
    event Action<WorkspaceOpened>? Opened;
    event Action<WorkspaceClosed>? Closed;
    event Action<WorkspacesReordered>? Reordered;

    Task<Workspace> OpenAsync(string path, CancellationToken ct);
    Task CloseAsync(RepoId id, CancellationToken ct);
    Workspace? Find(RepoId id);
    void Reorder(IReadOnlyList<RepoId> newOrder);
}
