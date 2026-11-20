#!/bin/bash
# 从 Resources/icon-source 的 SVG 生成 Dock AppIcon.icns + 菜单栏模板图。
# 正式产物已提交在 Resources/；本脚本供维护者本地改图标时使用。
# 依赖：rsvg-convert（brew install librsvg）、iconutil、sips
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG_APP="$REPO_ROOT/Resources/icon-source/icon.svg"
SVG_MENU="$REPO_ROOT/Resources/icon-source/menubar.svg"
ICONSET="$REPO_ROOT/Resources/AppIcon.iconset"
ICNS="$REPO_ROOT/Resources/AppIcon.icns"
MENU_DIR="$REPO_ROOT/Resources"
TMP="$REPO_ROOT/Resources/.icon-tmp"

if [ ! -f "$SVG_APP" ]; then
  echo "缺少 $SVG_APP" >&2
  exit 1
fi
if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "需要 rsvg-convert：brew install librsvg" >&2
  exit 1
fi

rm -rf "$TMP" "$ICONSET"
mkdir -p "$TMP" "$ICONSET"

# 先渲 1024 主图，再缩到各尺寸（保留 SVG 里的 squircle + 材质）。
MASTER="$TMP/master-1024.png"
rsvg-convert -w 1024 -h 1024 "$SVG_APP" -o "$MASTER"

entries=(
  "icon_16x16:16"
  "icon_16x16@2x:32"
  "icon_32x32:32"
  "icon_32x32@2x:64"
  "icon_128x128:128"
  "icon_128x128@2x:256"
  "icon_256x256:256"
  "icon_256x256@2x:512"
  "icon_512x512:512"
  "icon_512x512@2x:1024"
)
for entry in "${entries[@]}"; do
  name="${entry%%:*}"
  px="${entry##*:}"
  out="$ICONSET/${name}.png"
  if [ "$px" = "1024" ]; then
    cp "$MASTER" "$out"
  else
    sips -z "$px" "$px" "$MASTER" --out "$out" >/dev/null
  fi
  echo "written $name.png"
done

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "icns → $ICNS"

# 菜单栏模板：黑线稿，运行时 isTemplate = true
rsvg-convert -w 18 -h 18 "$SVG_MENU" -o "$MENU_DIR/MenuBarIcon.png"
rsvg-convert -w 36 -h 36 "$SVG_MENU" -o "$MENU_DIR/MenuBarIcon@2x.png"
echo "menubar → $MENU_DIR/MenuBarIcon.png"

rm -rf "$TMP"
echo "完成"
