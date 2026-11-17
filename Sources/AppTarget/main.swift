import AppKit

// OneBox 应用入口：Dock 图标 + 菜单栏图标并存（默认 regular 激活策略）。
let app = NSApplication.shared
let delegate: AppDelegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
