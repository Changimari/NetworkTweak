using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace NetworkTweak.UI;

/// <summary>トレイ用アイコンを動的に生成する（.ico ファイル不要）</summary>
public static class IconFactory
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr handle);

    /// <summary>電波バー風のアイコンを生成</summary>
    public static Icon CreateTrayIcon()
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);

            using var brush = new SolidBrush(Color.FromArgb(46, 139, 230));
            // 4本の電波バー（左から右に高くなる）
            g.FillRectangle(brush, 3, 22, 5, 7);
            g.FillRectangle(brush, 10, 16, 5, 13);
            g.FillRectangle(brush, 17, 10, 5, 19);
            g.FillRectangle(brush, 24, 4, 5, 25);
        }

        IntPtr hIcon = bmp.GetHicon();
        try
        {
            using var temp = Icon.FromHandle(hIcon);
            return (Icon)temp.Clone();
        }
        finally
        {
            DestroyIcon(hIcon);
        }
    }
}
