namespace GitOpen.Application.Workspaces;

public interface IWorkspacePersistence
{
    Task<IReadOnlyList<string>> GetOpenPathsAsync(CancellationToken ct);
    Task SaveOpenPathsAsync(IReadOnlyList<string> paths, CancellationToken ct);
}
