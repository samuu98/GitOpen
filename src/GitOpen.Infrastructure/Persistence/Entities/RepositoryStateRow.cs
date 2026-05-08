namespace GitOpen.Infrastructure.Persistence.Entities;

public class RepositoryStateRow
{
    public Guid RepositoryId { get; set; }
    public string? LastBranchFullName { get; set; }
    public string? LastSelectedSha { get; set; }
    public int ScrollOffset { get; set; }
}
