using GitOpen.Infrastructure.Persistence.Entities;
using Microsoft.EntityFrameworkCore;

namespace GitOpen.Infrastructure.Persistence;

public class GitOpenDbContext : DbContext
{
    public DbSet<RepositoryRow> Repositories => Set<RepositoryRow>();
    public DbSet<RepositoryStateRow> RepositoryStates => Set<RepositoryStateRow>();
    public DbSet<WindowRow> Windows => Set<WindowRow>();
    public DbSet<SettingRow> Settings => Set<SettingRow>();
    public DbSet<ActivityLogRow> ActivityLog => Set<ActivityLogRow>();

    public GitOpenDbContext() { }
    public GitOpenDbContext(DbContextOptions<GitOpenDbContext> opts) : base(opts) { }

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    {
        if (!optionsBuilder.IsConfigured)
            optionsBuilder.UseSqlite($"Data Source={PathProvider.StateDbPath()}");
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<RepositoryRow>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Path).IsUnique();
            e.Property(x => x.Path).IsRequired();
            e.Property(x => x.DisplayName).IsRequired();
        });
        modelBuilder.Entity<RepositoryStateRow>().HasKey(x => x.RepositoryId);
        modelBuilder.Entity<WindowRow>().HasKey(x => x.Id);
        modelBuilder.Entity<SettingRow>().HasKey(x => x.Key);
        modelBuilder.Entity<ActivityLogRow>().HasKey(x => x.Id);
    }
}
