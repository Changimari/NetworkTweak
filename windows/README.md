# NetworkTweak for Windows

macOS 版 NetworkTweak の Windows 移植版。
**タスクトレイ（通知領域・画面右下）に常駐する**ネットワーク設定ユーティリティです。
DHCP と固定IPを頻繁に切り替える人向け。

## 機能

- **タスクトレイ常駐** - ウィンドウを閉じても通知領域に常駐。トレイアイコンのクリック/ダブルクリックで再表示、右クリックメニューから終了
- **ネットワークアダプタ一覧表示** - 接続中のアダプタをリアルタイム表示（5秒ごとに自動更新）
- **DHCP/固定IP切り替え** - ワンクリックで IP 設定を変更（`netsh` を使用）
- **DNSプリセット** - Google DNS / Cloudflare DNS をボタン一発で設定
- **IPメモ機能** - よく使う IP アドレスをメモとして保存
  - フォルダ管理
  - ドラッグ&ドロップでフォルダ間移動
  - CSV エクスポート（Excel 対応の UTF-8 BOM 付き）
- **セグメント接続** - メモの IP と同じセグメント（/24）の空き IP を自動検索して固定IP接続
- **通信速度表示** - 上り/下りの速度をステータスバーに表示
- **外部IP表示** - グローバル IP アドレスを表示

## 動作環境

- Windows 10 / 11 (x64)
- [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0)（フレームワーク依存ビルドの場合）

> ネットワーク設定の変更（`netsh`）には管理者権限が必要です。
> アプリは `app.manifest` により**起動時に UAC で昇格**します。

## ビルド方法

[.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) が必要です。

```powershell
cd windows
dotnet build NetworkTweak.sln -c Release
```

### 単一 EXE として発行（ランタイム同梱・推奨）

```powershell
cd windows\NetworkTweak
dotnet publish -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
  -o publish
```

`publish\NetworkTweak.exe` が生成されます。ダブルクリックで起動すると UAC ダイアログが表示され、
承認するとタスクトレイに常駐します。

> 補足: Linux/macOS 上でも `EnableWindowsTargeting=true` によりビルド（コンパイル検証）は可能ですが、
> WinForms アプリの実行は Windows のみです。

## アーキテクチャ

```
NetworkTweak/
├─ Program.cs                  エントリポイント（多重起動防止 + トレイ起動）
├─ app.manifest                管理者権限要求 / 高DPI
├─ Models/                     データモデル（macOS 版 Data/Models 相当）
│   ├─ NetworkAdapter.cs
│   └─ IPMemo.cs
├─ Services/                   ビジネスロジック（macOS 版 Business 相当）
│   ├─ NetworkService.cs       netsh + NetworkInformation によるアダプタ操作
│   ├─ NetworkSpeedMonitor.cs  通信速度計測
│   ├─ ExternalIpService.cs    外部IP取得
│   ├─ SegmentConnector.cs     空きIP検索
│   └─ MemoStore.cs            IPメモ永続化（%APPDATA%\NetworkTweak\memos.json）
└─ UI/                         画面（macOS 版 Presentation 相当）
    ├─ TrayApplicationContext.cs  タスクトレイ常駐
    ├─ MainForm.cs               メインウィンドウ（ネットワーク / IPメモ）
    ├─ Dialogs.cs                入力・メモ編集ダイアログ
    └─ IconFactory.cs            トレイアイコン生成

```

### macOS 版とのコマンド対応

| macOS (`networksetup`)            | Windows (`netsh`)                                           |
| --------------------------------- | ---------------------------------------------------------- |
| `-setdhcp <svc>`                  | `interface ip set address name="<n>" source=dhcp`          |
| `-setmanual <svc> <ip> <mask> <gw>` | `interface ip set address name="<n>" static <ip> <mask> <gw> 1` |
| `-setdnsservers <svc> <dns...>`   | `interface ip set dns name="<n>" static <dns> primary` ほか |
| アダプタ列挙                       | `System.Net.NetworkInformation.NetworkInterface`           |

## ライセンス

Private use only.
