import AppKit

// OneBox 应用入口：菜单栏常驻；Dock 可见性由 AppSettings.showInDock 决定（默认隐藏）。
let app = NSApplication.shared
let delegate: AppDelegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
