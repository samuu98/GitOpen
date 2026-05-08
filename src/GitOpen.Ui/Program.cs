using GitOpen.Application.DependencyInjection;
using GitOpen.Application.Workspaces;
using GitOpen.Infrastructure.DependencyInjection;
using GitOpen.Infrastructure.Persistence;
using GitOpen.Ui;
using GitOpen.Ui.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Photino.Blazor;
using Serilog;

namespace GitOpen.Ui;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Information()
            .WriteTo.Console(formatProvider: null)
            .WriteTo.File(
                path: Path.Combine(PathProvider.LogDirectory(), "gitopen-.log"),
                rollingInterval: RollingInterval.Day,
                retainedFileCountLimit: 7,
                formatProvider: null)
            .CreateLogger();

        try
        {
            var builder = PhotinoBlazorAppBuilder.CreateDefault(args);
            builder.Services
                .AddLogging(lb => lb.AddSerilog())
                .AddGitOpenApplication()
                .AddGitOpenInfrastructure()
                .AddSingleton<IFolderPicker, PhotinoFolderPicker>();
            builder.RootComponents.Add<App>("app");

            var app = builder.Build();

            using (var scope = app.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<GitOpenDbContext>();
                db.Database.Migrate();
            }

            RehydrateWorkspaces(app.Services);

            var manager = app.Services.GetRequiredService<IWorkspaceManager>();
            manager.Opened    += _ => PersistAsync(app.Services);
            manager.Closed    += _ => PersistAsync(app.Services);
            manager.Reordered += _ => PersistAsync(app.Services);

            app.MainWindow
                .SetTitle("GitOpen")
                .SetSize(1400, 900)
                .SetResizable(true)
                .SetChromeless(true)
                .SetContextMenuEnabled(true)
                .SetDevToolsEnabled(true);

            AppDomain.CurrentDomain.UnhandledException += (s, e) =>
                Log.Fatal(e.ExceptionObject as Exception, "Unhandled exception");

            app.Run();
            return 0;
        }
        finally
        {
            Log.CloseAndFlush();
        }
    }

    private static void RehydrateWorkspaces(IServiceProvider sp)
    {
        using var scope = sp.CreateScope();
        var persistence = scope.ServiceProvider.GetRequiredService<IWorkspacePersistence>();
        var manager = scope.ServiceProvider.GetRequiredService<IWorkspaceManager>();
        var paths = persistence.GetOpenPathsAsync(default).GetAwaiter().GetResult();
        foreach (var p in paths)
        {
            if (!Directory.Exists(p))
            {
                Log.Warning("Workspace path no longer exists, skipping: {Path}", p);
                continue;
            }
            try
            {
                manager.OpenAsync(p, default).GetAwaiter().GetResult();
            }
            catch (Exception ex)
            {
                Log.Warning(ex, "Failed to reopen workspace {Path}", p);
            }
        }
    }

    private static void PersistAsync(IServiceProvider sp)
    {
        _ = Task.Run(async () =>
        {
            using var scope = sp.CreateScope();
            var p = scope.ServiceProvider.GetRequiredService<IWorkspacePersistence>();
            var m = scope.ServiceProvider.GetRequiredService<IWorkspaceManager>();
            var paths = m.All.Select(w => w.Location.Path).ToList();
            try
            {
                await p.SaveOpenPathsAsync(paths, default);
            }
            catch (Exception ex)
            {
                Log.Warning(ex, "Failed to persist workspaces");
            }
        });
    }
}
