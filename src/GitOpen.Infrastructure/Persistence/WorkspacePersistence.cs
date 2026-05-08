using System.Text.Json;
using GitOpen.Application.Workspaces;
using GitOpen.Infrastructure.Persistence.Entities;
using Microsoft.EntityFrameworkCore;

namespace GitOpen.Infrastructure.Persistence;

public sealed class WorkspacePersistence : IWorkspacePersistence
{
    private const string Key = "open_workspaces";
    private readonly GitOpenDbContext _db;
    public WorkspacePersistence(GitOpenDbContext db) => _db = db;

    public async Task<IReadOnlyList<string>> GetOpenPathsAsync(CancellationToken ct)
    {
        var row = await _db.Settings.FirstOrDefaultAsync(s => s.Key == Key, ct);
        if (row is null) return Array.Empty<string>();
        return JsonSerializer.Deserialize<List<string>>(row.ValueJson) ?? new List<string>();
    }

    public async Task SaveOpenPathsAsync(IReadOnlyList<string> paths, CancellationToken ct)
    {
        var row = await _db.Settings.FirstOrDefaultAsync(s => s.Key == Key, ct);
        var json = JsonSerializer.Serialize(paths);
        if (row is null)
            _db.Settings.Add(new SettingRow { Key = Key, ValueJson = json });
        else
            row.ValueJson = json;
        await _db.SaveChangesAsync(ct);
    }
}
