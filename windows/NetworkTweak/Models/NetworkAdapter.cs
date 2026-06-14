namespace NetworkTweak.Models;

/// <summary>アダプタ種別</summary>
public enum AdapterType
{
    WiFi,
    Ethernet,
    Other
}

/// <summary>IPv4 の設定情報</summary>
public class IPConfig
{
    public bool IsDhcp { get; set; } = true;
    public string? IPv4 { get; set; }
    public string? SubnetMask { get; set; }
    public string? Gateway { get; set; }
    public List<string> DnsServers { get; set; } = new();
}

/// <summary>ネットワークアダプタを表すモデル</summary>
public class NetworkAdapter
{
    /// <summary>NetworkInterface.Id（一意ID）</summary>
    public string Id { get; set; } = "";

    /// <summary>接続名（"イーサネット" / "Wi-Fi" 等）。netsh のキーにもなる</summary>
    public string Name { get; set; } = "";

    /// <summary>ハードウェアの説明</summary>
    public string Description { get; set; } = "";

    public string? MacAddress { get; set; }
    public AdapterType Type { get; set; }
    public bool IsConnected { get; set; }
    public IPConfig Config { get; set; } = new();

    public string StatusText => IsConnected ? "接続中" : "未接続";

    public override string ToString() => Name;
}
