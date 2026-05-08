using GitOpen.Application.Git;
using GitOpen.Application.Workspaces;
using GitOpen.Infrastructure.Git;
using GitOpen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace GitOpen.Infrastructure.DependencyInjection;

public static class InfrastructureModule
{
    public static IServiceCollection AddGitOpenInfrastructure(this IServiceCollection services)
    {
        services.AddDbContext<GitOpenDbContext>(opts =>
            opts.UseSqlite($"Data Source={PathProvider.StateDbPath()}"));
        services.AddScoped<IRepositoryRegistry, RepositoryRegistry>();
        services.AddScoped<IWorkspacePersistence, WorkspacePersistence>();
        services.AddSingleton<IGitReadOperations, LibGit2GitReadOperations>();
        return services;
    }
}
