# NetworkTweak

macOSメニューバー常駐のネットワーク設定ユーティリティ。
DHCPと固定IPを頻繁に切り替える人向け。

## 機能

- **ネットワークアダプタ一覧表示** - 接続中のアダプタをリアルタイム表示
- **DHCP/固定IP切り替え** - ワンクリックでIP設定を変更
- **DNSプリセット** - Google DNS / Cloudflare DNS をボタン一発で設定
- **IPメモ機能** - よく使うIPアドレスをメモとして保存
  - フォルダ管理
  - ドラッグ&ドロップで整理
  - CSVエクスポート
- **セグメント接続** - メモのIPと同じセグメントの空きIPを自動検索して接続
- **メニューバー速度表示** - 上り/下りの通信速度を表示
- **外部IP表示** - グローバルIPアドレスを表示

## 動作環境

- macOS 14.0 (Sonoma) 以降

## インストール

1. [Releases](../../releases)からDMGをダウンロード
2. DMGを開いてNetworkTweak.appをApplicationsにドラッグ
3. 初回起動時に管理者パスワードを入力（ネットワーク設定変更のため）

## ビルド方法

```bash
xcodebuild -scheme NetworkMenuBar -configuration Release build
```

## ライセンス

Private use only.
