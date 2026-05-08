using GitOpen.Application.DependencyInjection;
using GitOpen.Infrastructure.DependencyInjection;
using GitOpen.Infrastructure.Persistence;
using GitOpen.Ui;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Photino.Blazor;
using Serilog;

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .WriteTo.Console(formatProvider: null)
    .WriteTo.File(
        path: System.IO.Path.Combine(PathProvider.LogDirectory(), "gitopen-.log"),
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
        .AddGitOpenInfrastructure();
    builder.RootComponents.Add<App>("#app");

    var app = builder.Build();

    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<GitOpenDbContext>();
        db.Database.Migrate();
    }

    app.MainWindow
        .SetTitle("GitOpen")
        .SetSize(1400, 900);

    AppDomain.CurrentDomain.UnhandledException += (s, e) =>
        Log.Fatal(e.ExceptionObject as Exception, "Unhandled exception");

    app.Run();
}
finally
{
    Log.CloseAndFlush();
}
