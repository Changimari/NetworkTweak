using NetworkTweak.Models;
using NetworkTweak.Services;

namespace NetworkTweak.UI;

/// <summary>メインウィンドウ。macOS 版のポップオーバー相当（ネットワーク設定 + IPメモ）</summary>
public class MainForm : Form
{
    private readonly NetworkService _net = new();
    private readonly NetworkSpeedMonitor _speed = new();
    private readonly ExternalIpService _extIp = new();
    private readonly MemoStore _memos = new();

    private List<NetworkAdapter> _adapters = new();
    private bool _allowClose;

    // ネットワークタブ
    private readonly ListBox _adapterList = new();
    private readonly Label _detail = new();
    private readonly TextBox _ipBox = new();
    private readonly TextBox _maskBox = new();
    private readonly TextBox _gwBox = new();

    // メモタブ
    private readonly TreeView _tree = new();

    // レイアウト
    private SplitContainer? _netSplit;

    // ステータスバー
    private readonly ToolStripStatusLabel _speedLabel = new();
    private readonly ToolStripStatusLabel _extIpLabel = new();

    // タイマー
    private readonly System.Windows.Forms.Timer _speedTimer = new();
    private readonly System.Windows.Forms.Timer _refreshTimer = new();

    public MainForm()
    {
        Text = "NetworkTweak";
        Icon = IconFactory.CreateTrayIcon();
        ClientSize = new Size(640, 520);
        MinimumSize = new Size(560, 460);
        StartPosition = FormStartPosition.CenterScreen;

        var tabs = new TabControl { Dock = DockStyle.Fill };
        tabs.TabPages.Add(BuildNetworkTab());
        tabs.TabPages.Add(BuildMemoTab());

        var status = new StatusStrip();
        _speedLabel.Text = "速度: ↓ -  ↑ -";
        _extIpLabel.Text = "外部IP: 取得中...";
        _extIpLabel.Spring = true;
        _extIpLabel.TextAlign = ContentAlignment.MiddleRight;
        status.Items.Add(_speedLabel);
        status.Items.Add(_extIpLabel);

        Controls.Add(tabs);
        Controls.Add(status);

        // タイマー設定
        _speedTimer.Interval = 1000;
        _speedTimer.Tick += (_, _) => UpdateSpeed();
        _refreshTimer.Interval = 5000;
        _refreshTimer.Tick += (_, _) => ReloadAdapters();

        Load += (_, _) => OnFormLoad();
        FormClosing += OnFormClosing;
    }

    /// <summary>トレイメニューからの終了時に呼ぶ</summary>
    public void AllowClose() => _allowClose = true;

    private void OnFormLoad()
    {
        // フォームのサイズが確定した後に安全にスプリッタ位置を設定
        if (_netSplit != null)
        {
            try { _netSplit.SplitterDistance = 200; } catch { /* 幅が足りない場合は無視 */ }
        }

        ReloadAdapters();
        ReloadTree();
        _speedTimer.Start();
        _refreshTimer.Start();
        _ = RefreshExternalIpAsync();
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        // ×ボタンで閉じてもトレイに残す
        if (!_allowClose && e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
            _speedTimer.Stop();
            _refreshTimer.Stop();
        }
    }

    protected override void OnVisibleChanged(EventArgs e)
    {
        base.OnVisibleChanged(e);
        if (Visible)
        {
            _speedTimer.Start();
            _refreshTimer.Start();
            _ = RefreshExternalIpAsync();
        }
    }

    // ===== ネットワークタブ =====

    private TabPage BuildNetworkTab()
    {
        var page = new TabPage("ネットワーク");

        var split = new SplitContainer
        {
            Dock = DockStyle.Fill,
            FixedPanel = FixedPanel.Panel1
        };
        _netSplit = split;

        // 左: アダプタ一覧
        _adapterList.Dock = DockStyle.Fill;
        _adapterList.IntegralHeight = false;
        _adapterList.SelectedIndexChanged += (_, _) => UpdateDetail();
        var listLabel = new Label { Text = "アダプタ", Dock = DockStyle.Top, Height = 22, Padding = new Padding(4, 4, 0, 0) };
        split.Panel1.Controls.Add(_adapterList);
        split.Panel1.Controls.Add(listLabel);

        // 右: 詳細と操作
        var right = new Panel { Dock = DockStyle.Fill, AutoScroll = true, Padding = new Padding(10) };

        _detail.AutoSize = false;
        _detail.Dock = DockStyle.Top;
        _detail.Height = 130;
        _detail.Font = new Font(FontFamily.GenericMonospace, 9);

        var dhcpBtn = new Button { Text = "DHCP（自動）に切替", Dock = DockStyle.Top, Height = 32 };
        dhcpBtn.Click += (_, _) => ApplyDhcp();

        // 固定IP入力
        var staticGroup = new GroupBox { Text = "固定IP", Dock = DockStyle.Top, Height = 150, Padding = new Padding(8) };
        AddLabeledBox(staticGroup, "IPアドレス", _ipBox, 22);
        AddLabeledBox(staticGroup, "サブネットマスク", _maskBox, 54);
        AddLabeledBox(staticGroup, "ゲートウェイ", _gwBox, 86);
        var applyStatic = new Button { Text = "固定IPを適用", Left = 110, Top = 116, Width = 150, Height = 28 };
        applyStatic.Click += (_, _) => ApplyStatic();
        staticGroup.Controls.Add(applyStatic);

        // DNS プリセット
        var dnsGroup = new GroupBox { Text = "DNS", Dock = DockStyle.Top, Height = 70, Padding = new Padding(8) };
        var googleBtn = new Button { Text = "Google DNS", Left = 8, Top = 24, Width = 130, Height = 30 };
        googleBtn.Click += (_, _) => ApplyDns(new[] { "8.8.8.8", "8.8.4.4" });
        var cfBtn = new Button { Text = "Cloudflare DNS", Left = 146, Top = 24, Width = 130, Height = 30 };
        cfBtn.Click += (_, _) => ApplyDns(new[] { "1.1.1.1", "1.0.0.1" });
        var dnsAutoBtn = new Button { Text = "自動(DHCP)", Left = 284, Top = 24, Width = 110, Height = 30 };
        dnsAutoBtn.Click += (_, _) => ApplyDns(Array.Empty<string>());
        dnsGroup.Controls.Add(googleBtn);
        dnsGroup.Controls.Add(cfBtn);
        dnsGroup.Controls.Add(dnsAutoBtn);

        var refreshBtn = new Button { Text = "更新", Dock = DockStyle.Top, Height = 28 };
        refreshBtn.Click += (_, _) => ReloadAdapters();

        // Dock=Top は逆順に追加すると上から順に並ぶ
        right.Controls.Add(dnsGroup);
        right.Controls.Add(staticGroup);
        right.Controls.Add(dhcpBtn);
        right.Controls.Add(_detail);
        right.Controls.Add(refreshBtn);

        split.Panel2.Controls.Add(right);
        page.Controls.Add(split);
        return page;
    }

    private static void AddLabeledBox(Control parent, string label, TextBox box, int top)
    {
        var lbl = new Label { Text = label, Left = 8, Top = top + 3, Width = 96 };
        box.Left = 110;
        box.Top = top;
        box.Width = 180;
        parent.Controls.Add(lbl);
        parent.Controls.Add(box);
    }

    private NetworkAdapter? SelectedAdapter
        => _adapterList.SelectedIndex >= 0 && _adapterList.SelectedIndex < _adapters.Count
            ? _adapters[_adapterList.SelectedIndex]
            : null;

    private void ReloadAdapters()
    {
        try
        {
            var selectedId = SelectedAdapter?.Id;
            _adapters = _net.GetAdapters();

            _adapterList.BeginUpdate();
            _adapterList.Items.Clear();
            foreach (var a in _adapters)
            {
                string mark = a.IsConnected ? "●" : "○";
                _adapterList.Items.Add($"{mark} {a.Name}");
            }
            _adapterList.EndUpdate();

            // 選択を復元
            int idx = selectedId != null ? _adapters.FindIndex(a => a.Id == selectedId) : -1;
            if (idx < 0 && _adapters.Count > 0) idx = 0;
            if (idx >= 0) _adapterList.SelectedIndex = idx;
            else UpdateDetail();
        }
        catch (Exception ex)
        {
            _detail.Text = "アダプタ取得エラー: " + ex.Message;
        }
    }

    private void UpdateDetail()
    {
        var a = SelectedAdapter;
        if (a == null)
        {
            _detail.Text = "アダプタを選択してください。";
            return;
        }

        var c = a.Config;
        string method = c.IsDhcp ? "DHCP（自動）" : "固定IP（手動）";
        string dns = c.DnsServers.Count > 0 ? string.Join(", ", c.DnsServers) : "(自動)";

        _detail.Text =
            $"名前   : {a.Name}\n" +
            $"状態   : {a.StatusText}\n" +
            $"種別   : {a.Type}\n" +
            $"MAC    : {a.MacAddress ?? "-"}\n" +
            $"方式   : {method}\n" +
            $"IP     : {c.IPv4 ?? "-"}  /  {c.SubnetMask ?? "-"}\n" +
            $"GW     : {c.Gateway ?? "-"}\n" +
            $"DNS    : {dns}";

        // 固定IP欄に現在値をプリフィル
        _ipBox.Text = c.IPv4 ?? "";
        _maskBox.Text = c.SubnetMask ?? "255.255.255.0";
        _gwBox.Text = c.Gateway ?? "";
    }

    private void ApplyDhcp()
    {
        var a = SelectedAdapter;
        if (a == null) return;
        RunNetworkAction(() => _net.SetDhcp(a.Name), $"{a.Name} を DHCP に切り替えました。");
    }

    private void ApplyStatic()
    {
        var a = SelectedAdapter;
        if (a == null) return;

        string ip = _ipBox.Text.Trim();
        string mask = _maskBox.Text.Trim();
        string gw = _gwBox.Text.Trim();

        if (string.IsNullOrEmpty(ip) || string.IsNullOrEmpty(mask))
        {
            MessageBox.Show("IPアドレスとサブネットマスクを入力してください。", "NetworkTweak");
            return;
        }

        RunNetworkAction(() => _net.SetStaticIp(a.Name, ip, mask, gw),
            $"{a.Name} を固定IP {ip} に設定しました。");
    }

    private void ApplyDns(string[] servers)
    {
        var a = SelectedAdapter;
        if (a == null) return;
        string desc = servers.Length == 0 ? "自動(DHCP)" : string.Join(", ", servers);
        RunNetworkAction(() => _net.SetDnsServers(a.Name, servers),
            $"{a.Name} の DNS を {desc} に設定しました。");
    }

    private void RunNetworkAction(Action action, string successMessage)
    {
        try
        {
            UseWaitCursor = true;
            action();
            ReloadAdapters();
            _speedLabel.Text = successMessage;
        }
        catch (Exception ex)
        {
            MessageBox.Show("操作に失敗しました。\n\n" + ex.Message +
                "\n\n管理者として実行されているか確認してください。", "NetworkTweak",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        finally
        {
            UseWaitCursor = false;
        }
    }

    // ===== IPメモタブ =====

    private TabPage BuildMemoTab()
    {
        var page = new TabPage("IPメモ");

        _tree.Dock = DockStyle.Fill;
        _tree.HideSelection = false;
        _tree.AllowDrop = true;
        _tree.ItemDrag += Tree_ItemDrag;
        _tree.DragEnter += (_, e) => e.Effect = DragDropEffects.Move;
        _tree.DragOver += (_, e) => e.Effect = DragDropEffects.Move;
        _tree.DragDrop += Tree_DragDrop;
        _tree.NodeMouseDoubleClick += (_, _) => EditMemo();

        var toolbar = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 36, Padding = new Padding(2) };
        AddToolButton(toolbar, "フォルダ追加", AddFolder);
        AddToolButton(toolbar, "メモ追加", AddMemo);
        AddToolButton(toolbar, "編集", EditMemo);
        AddToolButton(toolbar, "削除", DeleteSelected);
        AddToolButton(toolbar, "セグメント接続", SegmentConnect);
        AddToolButton(toolbar, "CSV出力", ExportCsv);

        page.Controls.Add(_tree);
        page.Controls.Add(toolbar);
        return page;
    }

    private static void AddToolButton(Control parent, string text, Action onClick)
    {
        var btn = new Button { Text = text, AutoSize = true, Height = 28 };
        btn.Click += (_, _) => onClick();
        parent.Controls.Add(btn);
    }

    private void ReloadTree()
    {
        _tree.BeginUpdate();
        _tree.Nodes.Clear();

        foreach (var folder in _memos.Folders)
        {
            var fn = new TreeNode($"📁 {folder.Name}") { Tag = folder };
            foreach (var m in folder.Memos)
                fn.Nodes.Add(MemoNode(m));
            _tree.Nodes.Add(fn);
            fn.Expand();
        }

        foreach (var m in _memos.Memos)
            _tree.Nodes.Add(MemoNode(m));

        _tree.EndUpdate();
    }

    private static TreeNode MemoNode(IPMemo m)
        => new($"{m.Name}  ({m.IpAddress})") { Tag = m };

    private IPMemo? SelectedMemo => _tree.SelectedNode?.Tag as IPMemo;

    private Guid? TargetFolderId()
    {
        var node = _tree.SelectedNode;
        if (node?.Tag is IPMemoFolder f) return f.Id;
        if (node?.Tag is IPMemo && node.Parent?.Tag is IPMemoFolder pf) return pf.Id;
        return null;
    }

    private void AddFolder()
    {
        string? name = InputBox.Show("フォルダ名:", "フォルダ追加");
        if (string.IsNullOrWhiteSpace(name)) return;
        _memos.AddFolder(name);
        ReloadTree();
    }

    private void AddMemo()
    {
        using var dlg = new MemoEditForm();
        if (dlg.ShowDialog(this) != DialogResult.OK) return;
        _memos.AddMemo(TargetFolderId(), dlg.Result);
        ReloadTree();
    }

    private void EditMemo()
    {
        var memo = SelectedMemo;
        if (memo == null) return;
        using var dlg = new MemoEditForm(memo);
        if (dlg.ShowDialog(this) != DialogResult.OK) return;
        _memos.UpdateMemo(dlg.Result);
        ReloadTree();
    }

    private void DeleteSelected()
    {
        var node = _tree.SelectedNode;
        if (node == null) return;

        if (node.Tag is IPMemoFolder folder)
        {
            if (MessageBox.Show($"フォルダ「{folder.Name}」と中のメモを削除しますか？",
                    "確認", MessageBoxButtons.YesNo) != DialogResult.Yes) return;
            _memos.DeleteFolder(folder.Id);
        }
        else if (node.Tag is IPMemo memo)
        {
            if (MessageBox.Show($"メモ「{memo.Name}」を削除しますか？",
                    "確認", MessageBoxButtons.YesNo) != DialogResult.Yes) return;
            _memos.DeleteMemo(memo.Id);
        }

        ReloadTree();
    }

    private void ExportCsv()
    {
        var node = _tree.SelectedNode;
        IEnumerable<IPMemo> target;
        string defaultName;

        if (node?.Tag is IPMemoFolder folder)
        {
            target = folder.Memos;
            defaultName = folder.Name + ".csv";
        }
        else
        {
            // 選択フォルダがなければ全メモ
            target = _memos.Folders.SelectMany(f => f.Memos).Concat(_memos.Memos);
            defaultName = "memos.csv";
        }

        using var sfd = new SaveFileDialog
        {
            Filter = "CSV ファイル (*.csv)|*.csv",
            FileName = defaultName
        };
        if (sfd.ShowDialog(this) != DialogResult.OK) return;

        try
        {
            // Excel で文字化けしないよう UTF-8 BOM 付きで保存
            File.WriteAllText(sfd.FileName, MemoStore.ExportToCsv(target),
                new System.Text.UTF8Encoding(true));
            _speedLabel.Text = "CSV を出力しました。";
        }
        catch (Exception ex)
        {
            MessageBox.Show("CSV 出力に失敗しました。\n" + ex.Message, "NetworkTweak");
        }
    }

    private async void SegmentConnect()
    {
        var memo = SelectedMemo;
        if (memo == null)
        {
            MessageBox.Show("接続先のメモを選択してください。", "NetworkTweak");
            return;
        }

        var adapter = SelectedAdapter ?? _adapters.FirstOrDefault(a => a.IsConnected);
        if (adapter == null)
        {
            MessageBox.Show("接続中のアダプタが見つかりません。", "NetworkTweak");
            return;
        }

        if (MessageBox.Show(
                $"「{memo.Name}」({memo.IpAddress}) と同じセグメントの空きIPを探し、\n" +
                $"アダプタ「{adapter.Name}」に固定IPとして設定します。よろしいですか？",
                "セグメント接続", MessageBoxButtons.OKCancel) != DialogResult.OK)
            return;

        try
        {
            UseWaitCursor = true;
            _speedLabel.Text = "空きIPを検索中...";

            string? freeIp = await SegmentConnector.FindFreeIpAsync(memo.IpAddress);
            if (freeIp == null)
            {
                MessageBox.Show("空きIPが見つかりませんでした。", "NetworkTweak");
                return;
            }

            string gateway = SegmentConnector.GuessGateway(memo.IpAddress);
            _net.SetStaticIp(adapter.Name, freeIp, "255.255.255.0", gateway);
            ReloadAdapters();
            _speedLabel.Text = $"{adapter.Name} を {freeIp} に設定しました（GW {gateway}）。";
        }
        catch (Exception ex)
        {
            MessageBox.Show("セグメント接続に失敗しました。\n" + ex.Message, "NetworkTweak");
        }
        finally
        {
            UseWaitCursor = false;
        }
    }

    // ----- ドラッグ&ドロップでメモを移動 -----

    private void Tree_ItemDrag(object? sender, ItemDragEventArgs e)
    {
        if (e.Item is TreeNode node && node.Tag is IPMemo)
            DoDragDrop(node, DragDropEffects.Move);
    }

    private void Tree_DragDrop(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetData(typeof(TreeNode)) is not TreeNode dragged) return;
        if (dragged.Tag is not IPMemo memo) return;

        var targetPoint = _tree.PointToClient(new Point(e.X, e.Y));
        var targetNode = _tree.GetNodeAt(targetPoint);

        // ドロップ先がフォルダ、またはフォルダ内メモならそのフォルダへ。空白なら null（トップレベル）
        Guid? targetFolderId = null;
        if (targetNode?.Tag is IPMemoFolder folder)
            targetFolderId = folder.Id;
        else if (targetNode?.Tag is IPMemo && targetNode.Parent?.Tag is IPMemoFolder parentFolder)
            targetFolderId = parentFolder.Id;

        _memos.MoveMemo(memo.Id, targetFolderId);
        ReloadTree();
    }

    // ===== ステータスバー =====

    private void UpdateSpeed()
    {
        _speed.Sample();
        _speedLabel.Text =
            $"速度: ↓ {NetworkSpeedMonitor.Format(_speed.DownloadBps)}  " +
            $"↑ {NetworkSpeedMonitor.Format(_speed.UploadBps)}";
    }

    private async Task RefreshExternalIpAsync()
    {
        string? ip = await _extIp.GetAsync();
        if (!IsDisposed)
            _extIpLabel.Text = ip != null ? $"外部IP: {ip}" : "外部IP: 取得失敗";
    }
}
