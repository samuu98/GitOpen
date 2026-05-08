using GitOpen.Domain.Repositories;

namespace GitOpen.Application.Workspaces;

public sealed class WorkspaceManager : IWorkspaceManager
{
    private readonly IRepositoryRegistry _registry;
    private readonly List<Workspace> _open = new();
    private readonly object _lock = new();

    public WorkspaceManager(IRepositoryRegistry registry) => _registry = registry;

    public IReadOnlyList<Workspace> All
    {
        get { lock (_lock) return _open.ToList(); }
    }

    public event Action<WorkspaceOpened>? Opened;
    public event Action<WorkspaceClosed>? Closed;
    public event Action<WorkspacesReordered>? Reordered;

    public async Task<Workspace> OpenAsync(string path, CancellationToken ct)
    {
        var loc = await _registry.AddAsync(path, ct);
        Workspace ws;
        bool fresh;
        lock (_lock)
        {
            var existing = _open.FirstOrDefault(w => w.Location.Id == loc.Id);
            if (existing is not null) return existing;
            ws = new Workspace(loc);
            _open.Add(ws);
            fresh = true;
        }
        if (fresh) Opened?.Invoke(new WorkspaceOpened(loc));
        await _registry.TouchLastOpenedAsync(loc.Id, ct);
        return ws;
    }

    public Task CloseAsync(RepoId id, CancellationToken ct)
    {
        bool removed;
        lock (_lock)
        {
            var ws = _open.FirstOrDefault(w => w.Location.Id == id);
            removed = ws is not null && _open.Remove(ws);
        }
        if (removed) Closed?.Invoke(new WorkspaceClosed(id));
        return Task.CompletedTask;
    }

    public Workspace? Find(RepoId id)
    {
        lock (_lock) return _open.FirstOrDefault(w => w.Location.Id == id);
    }

    public void Reorder(IReadOnlyList<RepoId> newOrder)
    {
        lock (_lock)
        {
            var dict = _open.ToDictionary(w => w.Location.Id);
            _open.Clear();
            foreach (var id in newOrder)
                if (dict.TryGetValue(id, out var ws)) _open.Add(ws);
        }
        Reordered?.Invoke(new WorkspacesReordered(newOrder));
    }
}
