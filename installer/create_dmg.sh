#!/bin/bash

# NetworkTweak DMG Creator
# 美しいインストーラーDMGを作成するスクリプト

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$PROJECT_DIR/DerivedData/Build/Products/Release/NetworkTweak.app"
DMG_NAME="NetworkTweak"
DMG_PATH="$BUILD_DIR/${DMG_NAME}.dmg"
TEMP_DMG_PATH="$BUILD_DIR/${DMG_NAME}_temp.dmg"
STAGING_DIR="$BUILD_DIR/dmg_staging"

# クリーンアップ
rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH" "$TEMP_DMG_PATH"
mkdir -p "$BUILD_DIR"
mkdir -p "$STAGING_DIR"

echo "📦 DMGステージング準備中..."

# アプリをコピー
cp -R "$APP_PATH" "$STAGING_DIR/"

# Applicationsへのシンボリックリンク
ln -s /Applications "$STAGING_DIR/Applications"

# READMEファイルを作成
cat > "$STAGING_DIR/はじめにお読みください.txt" << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                    NetworkTweak インストール手順                   ║
╚══════════════════════════════════════════════════════════════════╝

【インストール方法】
  NetworkTweak.app を Applications フォルダにドラッグ＆ドロップ

【初回起動時の設定】
  アプリを起動すると、以下の許可を求められる場合があります：

  1. 「ローカルネットワーク」へのアクセス許可
     → ネットワーク情報を取得するために必要です
     → 「許可」を選択してください

  2. 「ネットワーク設定の変更」の管理者権限
     → IPアドレスやDNSの変更に必要です
     → パスワードを入力して許可してください

【許可を後から変更する場合】
  システム設定 → プライバシーとセキュリティ → ローカルネットワーク
  から NetworkTweak の許可を確認できます。

【サポート】
  問題がある場合は GitHub Issues でお知らせください：
  https://github.com/Changimari/NetworkTweak/issues

EOF

echo "📀 一時DMG作成中..."

# 一時的な読み書き可能なDMGを作成
hdiutil create -srcfolder "$STAGING_DIR" -volname "$DMG_NAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW "$TEMP_DMG_PATH"

echo "🎨 DMGウィンドウをカスタマイズ中..."

# DMGをマウント
MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify "$TEMP_DMG_PATH")
DEVICE=$(echo "$MOUNT_OUTPUT" | grep "Apple_HFS" | awk '{print $1}')
MOUNT_POINT="/Volumes/$DMG_NAME"

sleep 2

# AppleScriptでFinderウィンドウをカスタマイズ
osascript << EOF
tell application "Finder"
    tell disk "$DMG_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 200, 900, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set background color of viewOptions to {60000, 60000, 65535}

        -- アイコンの位置を設定（エラーを無視）
        try
            set position of item "NetworkTweak.app" of container window to {130, 150}
        end try
        try
            set position of item "Applications" of container window to {370, 150}
        end try
        try
            set position of item "はじめにお読みください.txt" of container window to {250, 280}
        end try

        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

# .DS_Storeを確実に保存
sync

# アンマウント
hdiutil detach "$DEVICE"

echo "🔒 最終DMG作成中..."

# 読み取り専用の圧縮DMGに変換
hdiutil convert "$TEMP_DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

# 一時ファイルを削除
rm -f "$TEMP_DMG_PATH"
rm -rf "$STAGING_DIR"

echo "✅ DMG作成完了: $DMG_PATH"
