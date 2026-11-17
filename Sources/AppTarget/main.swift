import AppKit

// OneBox 菜单栏应用入口（LSUIElement：只显示菜单栏，不进 Dock）。
let app = NSApplication.shared
let delegate: AppDelegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
