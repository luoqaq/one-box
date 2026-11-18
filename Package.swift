// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OneBox",
    platforms: [.macOS("15.2")],
    products: [
        .executable(name: "OneBox", targets: ["AppTarget"])
    ],
    targets: [
        .target(name: "HotKeys"),
        .target(name: "ToolRegistry"),
        .target(name: "ClipboardStore"),
        .target(name: "CaptureStore"),
        .target(name: "ClipboardHistory", dependencies: ["ClipboardStore"]),
        .target(name: "Annotation"),
        .target(name: "ScreenCapture", dependencies: ["Annotation"]),
        .target(name: "ColorPicker"),
        .target(name: "ToolLauncherUI", dependencies: ["ToolRegistry"]),
        .target(
            name: "OneBoxUI",
            dependencies: [
                "HotKeys",
                "ToolRegistry",
                "ToolLauncherUI",
                "ClipboardHistory",
                "ClipboardStore",
                "CaptureStore",
                "ScreenCapture",
                "Annotation",
                "ColorPicker",
            ]
        ),
        .executableTarget(
            name: "AppTarget",
            dependencies: [
                "HotKeys",
                "ToolRegistry",
                "ToolLauncherUI",
                "OneBoxUI",
                "ClipboardHistory",
                "ClipboardStore",
                "CaptureStore",
                "ScreenCapture",
                "Annotation",
                "ColorPicker",
            ]
        ),
        .testTarget(name: "HotKeysTests", dependencies: ["HotKeys"]),
        .testTarget(name: "ClipboardStoreTests", dependencies: ["ClipboardStore"]),
        .testTarget(name: "CaptureStoreTests", dependencies: ["CaptureStore"]),
        .testTarget(name: "ClipboardHistoryTests", dependencies: ["ClipboardHistory"]),
        .testTarget(name: "AnnotationTests", dependencies: ["Annotation"]),
        .testTarget(name: "ScreenCaptureTests", dependencies: ["ScreenCapture"]),
        .testTarget(name: "ColorPickerTests", dependencies: ["ColorPicker"]),
    ],
    swiftLanguageModes: [.v5]
)
