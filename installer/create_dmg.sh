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
BG_IMAGE="$SCRIPT_DIR/dmg_background.png"

# クリーンアップ
rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH" "$TEMP_DMG_PATH"
mkdir -p "$BUILD_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$STAGING_DIR/.background"

echo "🎨 背景画像を作成中..."

# 背景画像を作成（矢印付き）
python3 - "$SCRIPT_DIR" << 'PYTHON_EOF'
import sys
import os
from PIL import Image, ImageDraw

script_dir = sys.argv[1]

# 画像サイズ（ウィンドウサイズに合わせる: 660x450）
width, height = 660, 450

# 背景色（薄いグレー）
bg_color = (240, 240, 245)

# 画像を作成
img = Image.new('RGB', (width, height), bg_color)
draw = ImageDraw.Draw(img)

# 矢印の色（青）
arrow_color = (80, 140, 220)

# 矢印を描画（アプリ位置からApplications位置へ）
# アプリ: x=140, Applications: x=520
# 30%短くする
arrow_start_x = 230
arrow_end_x = 430
arrow_y = 180

# 矢印の本体（太い線）
for offset in range(-4, 5):
    draw.line([(arrow_start_x, arrow_y + offset), (arrow_end_x - 30, arrow_y + offset)], fill=arrow_color, width=1)

# 矢印の先端（三角形）
draw.polygon([
    (arrow_end_x, arrow_y),
    (arrow_end_x - 40, arrow_y - 25),
    (arrow_end_x - 40, arrow_y + 25)
], fill=arrow_color)

# 保存
output_path = os.path.join(script_dir, "dmg_background.png")
img.save(output_path)
print(f"背景画像を保存: {output_path}")
PYTHON_EOF

# Pillowがない場合はsipsで簡易的な背景を作成
if [ ! -f "$BG_IMAGE" ]; then
    echo "⚠️ Pythonで背景作成失敗、シンプルな背景を使用..."
    # 空のPNGを作成（sipsで）
    sips -z 450 660 --setProperty format png "$APP_PATH/Contents/Resources/AppIcon.icns" --out "$BG_IMAGE" 2>/dev/null || true
fi

echo "📦 DMGステージング準備中..."

# アプリをコピー
cp -R "$APP_PATH" "$STAGING_DIR/"

# Applicationsへのシンボリックリンク
ln -s /Applications "$STAGING_DIR/Applications"

# 背景画像をコピー
if [ -f "$BG_IMAGE" ]; then
    cp "$BG_IMAGE" "$STAGING_DIR/.background/background.png"
fi

# READMEファイルを作成
cat > "$STAGING_DIR/はじめにお読みください.txt" << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                       NetworkTweak インストール手順                            ║
╚══════════════════════════════════════════════════════════════════════════════╝

【インストール方法】
  1. NetworkTweak.app を Applications フォルダにドラッグ＆ドロップ
  2. Applicationsフォルダから NetworkTweak を起動

【初回起動時の注意】
  「開発元を確認できないため開けません」と表示された場合：

  方法1: 右クリック（またはControl+クリック）→「開く」→「開く」
  方法2: システム設定 → プライバシーとセキュリティ → 「このまま開く」

【アプリ起動後の許可設定】
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

# 一時的な読み書き可能なDMGを作成（サイズを大きめに）
hdiutil create -srcfolder "$STAGING_DIR" -volname "$DMG_NAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size 10m "$TEMP_DMG_PATH"

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
        -- ウィンドウサイズを大きく: 660x450
        set the bounds of container window to {300, 100, 960, 550}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100

        -- 背景画像を設定
        try
            set background picture of viewOptions to file ".background:background.png"
        on error
            set background color of viewOptions to {60000, 60000, 63000}
        end try

        -- アイコンの位置を設定
        try
            set position of item "NetworkTweak.app" of container window to {140, 180}
        end try
        try
            set position of item "Applications" of container window to {520, 180}
        end try
        try
            set position of item "はじめにお読みください.txt" of container window to {330, 80}
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
