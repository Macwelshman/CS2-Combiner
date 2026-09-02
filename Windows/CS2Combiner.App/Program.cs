using Avalonia;

namespace CS2Combiner.App;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        if (AppUpdateManager.TryRunInstaller(args))
        {
            return;
        }
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
