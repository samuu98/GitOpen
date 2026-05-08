using GitOpen.Domain.Commits;
using GitOpen.Domain.Repositories;

namespace GitOpen.Application.Workspaces;

public sealed class Workspace
{
    public RepoLocation Location { get; }
    public string? SelectedBranchFullName { get; set; }
    public CommitSha? SelectedSha { get; set; }
    public int ScrollOffset { get; set; }

    public Workspace(RepoLocation location) => Location = location;
}
