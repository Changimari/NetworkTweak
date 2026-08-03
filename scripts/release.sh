#!/bin/bash
#
# NetworkTweak リリーススクリプト（Developer ID署名 + 公証 + Sparkle自動アップデート）
#
# 事前準備（初回のみ）:
#   1. Apple Developer Program 加入済みで「Developer ID Application」証明書をキーチェーンに導入
#   2. 公証用の認証情報を保存:
#        xcrun notarytool store-credentials "NOTARY_PROFILE" \
#          --apple-id "your@appleid.com" --team-id "TEAMID" --password "app-specific-password"
#   3. Sparkleの署名鍵は既にキーチェーンに生成済み（generate_keys 実行済み）
#
# 使い方:
#   ./scripts/release.sh
#
set -euo pipefail

# ===== 設定（自分の環境に合わせて編集） =====
DEVELOPER_ID="Developer ID Application: Ryosuke Sakai (H4Z24X5BQE)"   # security find-identity -v -p codesigning で確認済み
NOTARY_PROFILE="NOTARY_PROFILE"                               # 下記 store-credentials で作成する名前（未設定）
GITHUB_REPO="Changimari/NetworkTweak"
# ============================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

SPARKLE_BIN="$PROJECT_DIR/.spm/artifacts/sparkle/Sparkle/bin"
BUILD_DIR="$PROJECT_DIR/build"
EXPORT_DIR="$BUILD_DIR/export"
STAGING_DIR="$BUILD_DIR/appcast_staging"
DERIVED="$BUILD_DIR/DerivedData"

# バージョンを project.yml から取得
VERSION=$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')
TAG="v${VERSION}"
ZIP_NAME="NetworkTweak-${VERSION}.zip"

echo "▶︎ リリースビルド: NetworkTweak ${VERSION}"

rm -rf "$EXPORT_DIR" "$STAGING_DIR"
mkdir -p "$EXPORT_DIR" "$STAGING_DIR"

# 1. プロジェクト再生成 & リリースビルド（Developer ID署名）
xcodegen generate
xcodebuild -project NetworkMenuBar.xcodeproj -scheme NetworkMenuBar \
    -configuration Release \
    -clonedSourcePackagesDirPath "$PROJECT_DIR/.spm" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
    CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    build

APP_PATH="$DERIVED/Build/Products/Release/NetworkTweak.app"
[ -d "$APP_PATH" ] || { echo "✗ ビルド成果物が見つかりません: $APP_PATH"; exit 1; }

# 2. 公証用にzip化して公証 → ステープル
echo "▶︎ 公証中..."
NOTARIZE_ZIP="$BUILD_DIR/notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"

# 3. 配布用zipを作成（Sparkleが配布するのはこれ）
echo "▶︎ 配布zip作成: $ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$STAGING_DIR/$ZIP_NAME"

# 4. appcast を生成（EdDSA署名付き。enclosure URLはGitHub Releaseの配布先を指す）
echo "▶︎ appcast生成..."
"$SPARKLE_BIN/generate_appcast" "$STAGING_DIR" \
    --download-url-prefix "https://github.com/${GITHUB_REPO}/releases/download/${TAG}/"

# 生成された appcast.xml をリポジトリ直下へ
cp "$STAGING_DIR/appcast.xml" "$PROJECT_DIR/appcast.xml"

echo ""
echo "✅ ビルド・公証・appcast生成 完了"
echo ""
echo "次の手順:"
echo "  1. GitHub Release を作成し zip をアップロード:"
echo "       gh release create ${TAG} \"$STAGING_DIR/$ZIP_NAME\" --title \"${TAG}\" --notes \"...\""
echo "  2. 更新した appcast.xml を main にコミット&プッシュ:"
echo "       git add appcast.xml && git commit -m \"Release ${TAG}\" && git push"
echo ""
echo "  → これで既存ユーザーはアプリ内「Check for Updates」で自動更新されます。"
