using System.Net.NetworkInformation;

namespace NetworkTweak.Services;

/// <summary>ネットワーク速度を監視するクラス。macOS 版 NetworkSpeedMonitor 相当</summary>
public class NetworkSpeedMonitor
{
    private long _prevRx;
    private long _prevTx;
    private DateTime _prevTime;

    public double DownloadBps { get; private set; }
    public double UploadBps { get; private set; }

    /// <summary>1サンプル分の速度を計測して内部状態を更新</summary>
    public void Sample()
    {
        long rx = 0, tx = 0;

        foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            if (ni.OperationalStatus != OperationalStatus.Up) continue;

            try
            {
                var s = ni.GetIPv4Statistics();
                rx += s.BytesReceived;
                tx += s.BytesSent;
            }
            catch { /* 統計を取得できないアダプタは無視 */ }
        }

        var now = DateTime.UtcNow;
        if (_prevTime != default)
        {
            double dt = (now - _prevTime).TotalSeconds;
            if (dt > 0)
            {
                // カウンタが巻き戻った場合（再起動等）は更新しない
                if (rx >= _prevRx) DownloadBps = (rx - _prevRx) / dt;
                if (tx >= _prevTx) UploadBps = (tx - _prevTx) / dt;
            }
        }

        _prevRx = rx;
        _prevTx = tx;
        _prevTime = now;
    }

    public void Reset()
    {
        _prevTime = default;
        DownloadBps = 0;
        UploadBps = 0;
    }

    /// <summary>速度を人間が読める形式にフォーマット（バイト毎秒）</summary>
    public static string Format(double bytesPerSecond)
    {
        if (bytesPerSecond < 1024)
            return $"{bytesPerSecond:0} B/s";
        if (bytesPerSecond < 1024 * 1024)
            return $"{bytesPerSecond / 1024:0.0} KB/s";
        if (bytesPerSecond < 1024d * 1024 * 1024)
            return $"{bytesPerSecond / (1024 * 1024):0.0} MB/s";
        return $"{bytesPerSecond / (1024d * 1024 * 1024):0.0} GB/s";
    }
}
