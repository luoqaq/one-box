#!/bin/bash
# OneBox .app 打包脚本：SwiftPM release 构建 + Info.plist + ad-hoc 签名。
# 用法：./Scripts/package-app.sh [输出目录]（默认 Scripts/build）
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/Scripts/build}"
APP_NAME="OneBox"
BUNDLE_ID="com.onebox.app"
SDK_ROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk}"
# 强制用 CLT 工具链：避免 xcode-select 指向未同意 license 的 Xcode。
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"

# 1) SwiftPM release 构建（必须用 15.2 SDK：默认 27 SDK 的 SwiftUI @State 宏在纯 CLT 下缺插件）。
cd "$REPO_ROOT"
echo "==> swift build -c release"
SDKROOT="$SDK_ROOT" swift build -c release --scratch-path "$REPO_ROOT/.build"

BIN="$REPO_ROOT/.build/release/$APP_NAME"
if [ ! -f "$BIN" ]; then
    echo "错误：未找到构建产物 $BIN" >&2
    exit 1
fi

# 2) 组装 .app。
APP_ROOT="$OUT_DIR/$APP_NAME.app"
CONTENTS="$APP_ROOT/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
rm -rf "$APP_ROOT"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN" "$MACOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>OneBox</string>
    <key>CFBundleDisplayName</key>
    <string>OneBox</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.2</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# 3) ad-hoc 签名（本机直接运行）。
echo "==> codesign (ad-hoc)"
codesign --force --deep --sign - "$APP_ROOT"

echo "==> 完成：$APP_ROOT"
echo "    双击运行或 open \"$APP_ROOT\""
