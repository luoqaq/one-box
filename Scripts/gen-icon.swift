// OneBox 图标生成：品牌蓝圆角底 + 白色 2x2 网格（与菜单栏 SF Symbol 对应）。
// 用法：swiftc Scripts/gen-icon.swift -o /tmp/gen-icon && /tmp/gen-icon && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

let brandBlue = NSColor(srgbRed: 0, green: 122.0 / 255.0, blue: 1, alpha: 1)

func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: s, height: s)

    // 圆角底
    let bg = NSBezierPath(
        roundedRect: rect.insetBy(dx: s * 0.02, dy: s * 0.02),
        xRadius: s * 0.225,
        yRadius: s * 0.225
    )
    brandBlue.setFill()
    bg.fill()

    // 2x2 网格
    NSColor.white.setFill()
    let margin = s * 0.17
    let gap = s * 0.085
    let cell = (s - 2 * margin - gap) / 2
    let radius = cell * 0.26
    for row in 0..<2 {
        for col in 0..<2 {
            let x = margin + CGFloat(col) * (cell + gap)
            let y = margin + CGFloat(row) * (cell + gap)
            let cellRect = NSRect(x: x, y: y, width: cell, height: cell)
            NSBezierPath(roundedRect: cellRect, xRadius: radius, yRadius: radius).fill()
        }
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("生成 PNG 失败：\(path)\n".data(using: .utf8)!)
        exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: path))
}

let root = FileManager.default.currentDirectoryPath
let iconset = "\(root)/Resources/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let entries: [(base: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for e in entries {
    writePNG(drawIcon(size: e.px), to: "\(iconset)/\(e.base).png")
    print("written \(e.base).png")
}
print("iconset 生成完成：\(iconset)")
