using System.Diagnostics;
using System.Net.Sockets;
using System.Net.NetworkInformation;
using NetworkTweak.Models;

namespace NetworkTweak.Services;

/// <summary>
/// netsh / System.Net.NetworkInformation を用いた
/// Windows のネットワーク設定管理。macOS 版 NetworkManager 相当。
/// </summary>
public class NetworkService
{
    /// <summary>全アダプタの情報を取得</summary>
    public List<NetworkAdapter> GetAdapters()
    {
        var list = new List<NetworkAdapter>();

        foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            // ループバックとトンネルは除外
            if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            if (ni.NetworkInterfaceType == NetworkInterfaceType.Tunnel) continue;

            var adapter = new NetworkAdapter
            {
                Id = ni.Id,
                Name = ni.Name,
                Description = ni.Description,
                MacAddress = FormatMac(ni.GetPhysicalAddress()),
                Type = MapType(ni.NetworkInterfaceType),
                IsConnected = ni.OperationalStatus == OperationalStatus.Up,
                Config = ReadConfig(ni)
            };
            list.Add(adapter);
        }

        // 接続中を上に、その後名前順
        return list
            .OrderByDescending(a => a.IsConnected)
            .ThenBy(a => a.Name)
            .ToList();
    }

    /// <summary>接続中のアダプタのみを返す</summary>
    public List<NetworkAdapter> GetConnectedAdapters()
        => GetAdapters().Where(a => a.IsConnected).ToList();

    private static IPConfig ReadConfig(NetworkInterface ni)
    {
        var cfg = new IPConfig();
        try
        {
            var props = ni.GetIPProperties();

            try
            {
                var v4 = props.GetIPv4Properties();
                cfg.IsDhcp = v4?.IsDhcpEnabled ?? true;
            }
            catch { /* 一部の仮想アダプタは IPv4 プロパティ非対応 */ }

            foreach (var ua in props.UnicastAddresses)
            {
                if (ua.Address.AddressFamily == AddressFamily.InterNetwork)
                {
                    cfg.IPv4 = ua.Address.ToString();
                    try { cfg.SubnetMask = ua.IPv4Mask?.ToString(); } catch { }
                    break;
                }
            }

            var gw = props.GatewayAddresses
                .FirstOrDefault(g => g.Address.AddressFamily == AddressFamily.InterNetwork);
            cfg.Gateway = gw?.Address.ToString();

            foreach (var dns in props.DnsAddresses)
            {
                if (dns.AddressFamily == AddressFamily.InterNetwork)
                    cfg.DnsServers.Add(dns.ToString());
            }
        }
        catch { /* 取得失敗時はデフォルト（DHCP）扱い */ }

        return cfg;
    }

    private static string? FormatMac(PhysicalAddress addr)
    {
        var bytes = addr.GetAddressBytes();
        if (bytes.Length == 0) return null;
        return string.Join(":", bytes.Select(b => b.ToString("X2")));
    }

    private static AdapterType MapType(NetworkInterfaceType type) => type switch
    {
        NetworkInterfaceType.Wireless80211 => AdapterType.WiFi,
        NetworkInterfaceType.Ethernet => AdapterType.Ethernet,
        NetworkInterfaceType.GigabitEthernet => AdapterType.Ethernet,
        NetworkInterfaceType.FastEthernetT => AdapterType.Ethernet,
        NetworkInterfaceType.FastEthernetFx => AdapterType.Ethernet,
        _ => AdapterType.Other
    };

    // MARK: - 設定変更（要管理者権限。app.manifest で起動時に昇格）

    /// <summary>DHCP（自動取得）に切り替え。DNS も自動に戻す</summary>
    public void SetDhcp(string name)
    {
        RunNetsh($"interface ip set address name=\"{name}\" source=dhcp");
        RunNetsh($"interface ip set dns name=\"{name}\" source=dhcp");
    }

    /// <summary>固定IPを設定</summary>
    public void SetStaticIp(string name, string ip, string mask, string? gateway)
    {
        if (string.IsNullOrWhiteSpace(gateway))
            RunNetsh($"interface ip set address name=\"{name}\" static {ip} {mask}");
        else
            RunNetsh($"interface ip set address name=\"{name}\" static {ip} {mask} {gateway} 1");
    }

    /// <summary>DNSサーバーを設定。空配列なら DHCP から自動取得に戻す</summary>
    public void SetDnsServers(string name, IList<string> servers)
    {
        if (servers.Count == 0)
        {
            RunNetsh($"interface ip set dns name=\"{name}\" source=dhcp");
            return;
        }

        RunNetsh($"interface ip set dns name=\"{name}\" static {servers[0]} primary");
        for (int i = 1; i < servers.Count; i++)
            RunNetsh($"interface ip add dns name=\"{name}\" {servers[i]} index={i + 1}");
    }

    /// <summary>緊急リセット: DHCP に戻す</summary>
    public void EmergencyResetToDhcp(string name) => SetDhcp(name);

    /// <summary>netsh コマンドを実行。失敗時は例外</summary>
    private static void RunNetsh(string arguments)
    {
        var psi = new ProcessStartInfo("netsh", arguments)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException("netsh の起動に失敗しました");

        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            string message = string.IsNullOrWhiteSpace(stderr) ? stdout : stderr;
            throw new InvalidOperationException(
                $"netsh コマンドが失敗しました (exit={process.ExitCode})\n{message.Trim()}");
        }
    }
}
