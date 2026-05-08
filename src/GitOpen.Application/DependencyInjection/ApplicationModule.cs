using GitOpen.Application.CommitGraph;
using GitOpen.Application.Workspaces;
using Microsoft.Extensions.DependencyInjection;

namespace GitOpen.Application.DependencyInjection;

public static class ApplicationModule
{
    public static IServiceCollection AddGitOpenApplication(this IServiceCollection services)
    {
        services.AddSingleton<IWorkspaceManager, WorkspaceManager>();
        services.AddSingleton<ICommitGraphLayout, CommitGraphLayout>();
        return services;
    }
}
