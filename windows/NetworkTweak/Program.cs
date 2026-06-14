using NetworkTweak.UI;

namespace NetworkTweak;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();

        // 多重起動を防止
        using var mutex = new Mutex(true, "NetworkTweak_SingleInstance_8f2a", out bool createdNew);
        if (!createdNew)
            return;

        Application.Run(new TrayApplicationContext());
    }
}
