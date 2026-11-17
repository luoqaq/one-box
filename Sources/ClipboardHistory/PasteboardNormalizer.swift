import AppKit
import ClipboardStore
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// pasteboard 读取与规范化：文本取纯文本；图片统一重编码为规范化 PNG。
public enum PasteboardNormalizer {

    /// 规范化结果：文本或图片二选一，附带内容哈希。
    public struct NormalizedContent: Equatable {
        /// 文本内容
        public let text: String?
        /// 图片规范化 PNG
        public let pngData: Data?
        /// SHA-256：文本按 UTF-8 字节，图片按规范化 PNG 字节
        public let hash: String

        /// text / image
        public var kind: ClipboardRecord.Kind {
            text != nil ? .text : .image
        }

        init(text: String?, pngData: Data?) {
            let bytes: Data
            if let text {
                self.text = text
                self.pngData = nil
                bytes = Data(text.utf8)
            } else if let pngData {
                self.text = nil
                self.pngData = pngData
                bytes = pngData
            } else {
                self.text = nil
                self.pngData = nil
                bytes = Data()
            }
            self.hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// 从 pasteboard 读取并规范化。无有效内容（含空白文本）返回 nil。
    public static func read(from pasteboard: PasteboardReading) -> NormalizedContent? {
        // 图片优先：复制图片时 pasteboard 可能同时带 URL 等文本，图片才是用户意图。
        if let png = normalizedImage(from: pasteboard) {
            return NormalizedContent(text: nil, pngData: png)
        }
        if let raw = pasteboard.string(forType: .string) {
            // 少于 1 个非空白字符的文本不入历史。
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return NormalizedContent(text: raw, pngData: nil)
        }
        return nil
    }

    // MARK: - 图片规范化

    /// 图片读取顺序：PNG、TIFF 直接数据，再退化到任意图片类型经 NSImage 解码。
    /// 所有来源最终走同一条「解码 → 固定 RGBA 位图 → PNG 编码」管线，保证 hash 稳定。
    private static func normalizedImage(from pasteboard: PasteboardReading) -> Data? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let png = pngFromEncoded(data) {
                return png
            }
        }
        // 退化路径：JPEG 等其他图片类型。
        for type in pasteboard.types {
            guard let uti = UTType(type.rawValue), uti.conforms(to: .image),
                  let data = pasteboard.data(forType: type),
                  let image = NSImage(data: data),
                  let cg = cgImage(from: image) else { continue }
            return pngFromCGImage(cg)
        }
        return nil
    }

    /// 解码任意编码（PNG/TIFF/JPEG…）的图片数据后重新编码为规范化 PNG。
    private static func pngFromEncoded(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return pngFromCGImage(cg)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.cgImage
    }

    /// 把 CGImage 绘制到固定参数（8bit RGBA、calibratedRGB）的位图再编码 PNG，
    /// 消除来源编码、色彩空间、预乘差异，同一图像无论以何种类型进入剪贴板，hash 一致。
    private static func pngFromCGImage(_ cg: CGImage) -> Data? {
        let w = cg.width
        let h = cg.height
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
              ) else { return nil }
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSImage(cgImage: cg, size: NSSize(width: w, height: h))
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
