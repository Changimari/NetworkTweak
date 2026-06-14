namespace NetworkTweak.UI;

/// <summary>
/// タスクトレイ（通知領域）常駐のアプリケーションコンテキスト。
/// ウィンドウを閉じてもトレイに残り、トレイメニューから終了する。
/// </summary>
public class TrayApplicationContext : ApplicationContext
{
    private readonly NotifyIcon _tray;
    private MainForm? _form;

    public TrayApplicationContext()
    {
        _tray = new NotifyIcon
        {
            Icon = IconFactory.CreateTrayIcon(),
            Visible = true,
            Text = "NetworkTweak"
        };

        var menu = new ContextMenuStrip();
        menu.Items.Add("開く(&O)", null, (_, _) => ShowForm());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("終了(&Q)", null, (_, _) => ExitApp());
        _tray.ContextMenuStrip = menu;

        _tray.DoubleClick += (_, _) => ShowForm();
        _tray.MouseClick += (_, e) =>
        {
            if (e.Button == MouseButtons.Left) ShowForm();
        };

        // 初回起動時にウィンドウを表示
        ShowForm();
    }

    private void ShowForm()
    {
        if (_form == null || _form.IsDisposed)
        {
            _form = new MainForm();
        }

        _form.Show();
        if (_form.WindowState == FormWindowState.Minimized)
            _form.WindowState = FormWindowState.Normal;
        _form.Activate();
        _form.BringToFront();
    }

    private void ExitApp()
    {
        _tray.Visible = false;
        _tray.Dispose();
        _form?.AllowClose();
        _form?.Close();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _tray.Visible = false;
            _tray.Dispose();
        }
        base.Dispose(disposing);
    }
}
