namespace GitOpen.Infrastructure.Persistence;

public static class PathProvider
{
    public static string ConfigDirectory()
    {
        var baseDir = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(baseDir))
        {
            var home = Environment.GetEnvironmentVariable("HOME") ?? Environment.CurrentDirectory;
            baseDir = Path.Combine(home, ".config");
        }
        var dir = Path.Combine(baseDir, "GitOpen");
        Directory.CreateDirectory(dir);
        return dir;
    }

    public static string StateDbPath() => Path.Combine(ConfigDirectory(), "state.db");
    public static string SettingsJsonPath() => Path.Combine(ConfigDirectory(), "settings.json");
    public static string LogDirectory()
    {
        var dir = Path.Combine(ConfigDirectory(), "logs");
        Directory.CreateDirectory(dir);
        return dir;
    }
}
