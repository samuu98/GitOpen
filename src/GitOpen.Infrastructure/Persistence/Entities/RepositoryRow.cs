namespace GitOpen.Infrastructure.Persistence.Entities;

public class RepositoryRow
{
    public Guid Id { get; set; }
    public string Path { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string? Color { get; set; }
    public DateTime LastOpenedUtc { get; set; }
    public int TabOrder { get; set; }
    public DateTime CreatedUtc { get; set; }
}
