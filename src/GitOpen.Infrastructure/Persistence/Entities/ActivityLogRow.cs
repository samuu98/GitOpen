namespace GitOpen.Infrastructure.Persistence.Entities;

public class ActivityLogRow
{
    public long Id { get; set; }
    public DateTime TimestampUtc { get; set; }
    public Guid? RepositoryId { get; set; }
    public string Operation { get; set; } = "";
    public bool Ok { get; set; }
    public string? Stdout { get; set; }
    public string? Stderr { get; set; }
}
