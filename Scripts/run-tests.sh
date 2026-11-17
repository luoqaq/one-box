#!/bin/bash
# OneBox 测试运行脚本。
#
# 环境约束（本机 CLT，无 Xcode）：
# - 构建 App 必须用 MacOSX15.2 SDK：默认 27 SDK 的 SwiftUI @State 宏缺 SwiftUIMacros 插件。
# - 跑测试必须用默认 SDK：15.2 SDK 的 stdlib 缺 SendableMetatype，Testing 模块无法解析。
# - 因此测试在 /tmp 独立包中运行，只包含非 SwiftUI 模块（UI 模块由 swift build 编译验证）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="/tmp/onebox-tests"
MODULES=(ToolRegistry ClipboardStore CaptureStore ClipboardHistory Annotation ScreenCapture)

rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT/Sources" "$TEST_ROOT/Tests"

for m in "${MODULES[@]}"; do
    cp -R "$REPO_ROOT/Sources/$m" "$TEST_ROOT/Sources/$m"
done
for m in "${MODULES[@]}"; do
    cp -R "$REPO_ROOT/Tests/${m}Tests" "$TEST_ROOT/Tests/${m}Tests"
done

cat > "$TEST_ROOT/Package.swift" <<'EOF'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OneBoxTests",
    platforms: [.macOS("15.2")],
    targets: [
        .target(name: "ToolRegistry"),
        .target(name: "ClipboardStore"),
        .target(name: "CaptureStore"),
        .target(name: "ClipboardHistory", dependencies: ["ClipboardStore"]),
        .target(name: "Annotation"),
        .target(name: "ScreenCapture"),
        .testTarget(name: "ToolRegistryTests", dependencies: ["ToolRegistry"]),
        .testTarget(name: "ClipboardStoreTests", dependencies: ["ClipboardStore"]),
        .testTarget(name: "CaptureStoreTests", dependencies: ["CaptureStore"]),
        .testTarget(name: "ClipboardHistoryTests", dependencies: ["ClipboardHistory"]),
        .testTarget(name: "AnnotationTests", dependencies: ["Annotation"]),
        .testTarget(name: "ScreenCaptureTests", dependencies: ["ScreenCapture"]),
    ],
    swiftLanguageModes: [.v5]
)
EOF

cd "$TEST_ROOT"
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift test \
    -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
