namespace NetworkTweak.Services;

/// <summary>グローバルIPアドレスを取得する</summary>
public class ExternalIpService
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(5) };

    public async Task<string?> GetAsync()
    {
        try
        {
            string ip = await Http.GetStringAsync("https://api.ipify.org");
            return ip.Trim();
        }
        catch
        {
            return null;
        }
    }
}
