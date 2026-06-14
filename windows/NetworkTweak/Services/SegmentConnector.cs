using System.Net.NetworkInformation;

namespace NetworkTweak.Services;

/// <summary>
/// メモのIPと同じセグメント（/24）の空きIPを探して接続するためのヘルパー。
/// macOS 版の「セグメント接続」相当。
/// </summary>
public static class SegmentConnector
{
    /// <summary>
    /// 対象IPと同じ /24 セグメント内で、応答のない（=空いている）IPを探す。
    /// 見つからなければ null。
    /// </summary>
    public static async Task<string?> FindFreeIpAsync(string targetIp, CancellationToken ct = default)
    {
        var parts = targetIp.Split('.');
        if (parts.Length != 4) return null;

        string prefix = $"{parts[0]}.{parts[1]}.{parts[2]}.";

        for (int host = 2; host <= 254; host++)
        {
            ct.ThrowIfCancellationRequested();

            string candidate = prefix + host;
            if (candidate == targetIp) continue;

            if (!await IsAliveAsync(candidate))
                return candidate;
        }

        return null;
    }

    /// <summary>対象IPの /24 から推測したゲートウェイ（x.x.x.1）</summary>
    public static string GuessGateway(string targetIp)
    {
        var parts = targetIp.Split('.');
        if (parts.Length != 4) return targetIp;
        return $"{parts[0]}.{parts[1]}.{parts[2]}.1";
    }

    private static async Task<bool> IsAliveAsync(string ip)
    {
        try
        {
            using var ping = new Ping();
            var reply = await ping.SendPingAsync(ip, 250);
            return reply.Status == IPStatus.Success;
        }
        catch
        {
            return false;
        }
    }
}
