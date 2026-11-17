import Foundation
import AppKit
import CoreGraphics
import ImageIO

/// 截图记录存储：captures/<uuid>.png + captures.sqlite，独立于剪贴板历史。
public actor CaptureStore {
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("OneBox", isDirectory: true)
    }

    private let root: URL
    private let db: SQLiteDatabase

    public init(directory: URL? = nil) throws {
        let root = directory ?? Self.defaultDirectory()
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("captures", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("capture-thumbnails", isDirectory: true), withIntermediateDirectories: true)
        self.db = try SQLiteDatabase(path: root.appendingPathComponent("captures.sqlite").path)
        try db.execute("""
        CREATE TABLE IF NOT EXISTS capture_records(
            id TEXT PRIMARY KEY,
            file TEXT NOT NULL,
            thumbnail_file TEXT,
            width INTEGER NOT NULL,
            height INTEGER NOT NULL,
            byte_count INTEGER NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_cap_created ON capture_records(created_at DESC);
        """)
    }

    /// 插入一条截图记录（PNG 数据落盘 + 缩略图）。
    @discardableResult
    public func insert(png: Data) throws -> CaptureRecord {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "OneBox.CaptureStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法解码 PNG 数据"])
        }
        let uuid = UUID().uuidString
        let rel = "captures/\(uuid).png"
        let thumbRel = "capture-thumbnails/\(uuid).png"
        try Self.atomicWrite(data: png, to: root.appendingPathComponent(rel))
        let thumb = Self.thumbnailPNG(from: image, maxPixel: 240)
        try Self.atomicWrite(data: thumb, to: root.appendingPathComponent(thumbRel))
        let record = CaptureRecord(
            file: rel,
            thumbnailFile: thumbRel,
            width: image.width,
            height: image.height,
            byteCount: png.count
        )
        try db.run("""
        INSERT OR IGNORE INTO capture_records
        (id, file, thumbnail_file, width, height, byte_count, created_at)
        VALUES (?,?,?,?,?,?,?);
        """, bind: { s in
            s.bindText(1, record.id.uuidString)
            s.bindText(2, record.file)
            s.bindText(3, record.thumbnailFile)
            s.bindInt(4, Int64(record.width))
            s.bindInt(5, Int64(record.height))
            s.bindInt(6, Int64(record.byteCount))
            s.bindDouble(7, record.createdAt.timeIntervalSince1970)
        })
        return record
    }

    public func records(search: String = "", limit: Int = 100) -> [CaptureRecord] {
        var sql = "SELECT * FROM capture_records"
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            sql += " WHERE file LIKE '%\(q.replacingOccurrences(of: "'", with: "''"))%'"
        }
        sql += " ORDER BY created_at DESC LIMIT \(max(1, limit));"
        var results: [CaptureRecord] = []
        try? db.run(sql, row: { s in results.append(Self.parse(s)) })
        return results
    }

    public func record(id: UUID) -> CaptureRecord? {
        var result: CaptureRecord?
        try? db.run("SELECT * FROM capture_records WHERE id = ? LIMIT 1;", bind: { s in
            s.bindText(1, id.uuidString)
        }, row: { s in
            if result == nil { result = Self.parse(s) }
        })
        return result
    }

    public func delete(id: UUID) throws {
        if let r = record(id: id) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(r.file))
            if let t = r.thumbnailFile {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(t))
            }
        }
        try db.run("DELETE FROM capture_records WHERE id = ?;", bind: { s in
            s.bindText(1, id.uuidString)
        })
    }

    public func clear() throws {
        var files: [String] = []
        try db.run("SELECT file, thumbnail_file FROM capture_records;", row: { s in
            files.append(s.text(0) ?? "")
            if let t = s.text(1) { files.append(t) }
        })
        try db.run("DELETE FROM capture_records;")
        for f in files { try? FileManager.default.removeItem(at: root.appendingPathComponent(f)) }
    }

    /// 超数量/超天数清理（默认 100 张或 30 天）。返回删除条数。
    @discardableResult
    public func enforceRetention(limit: Int, days: Int) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        var removed: [CaptureRecord] = []
        try db.run("SELECT * FROM capture_records WHERE created_at < ?;", bind: { s in
            s.bindDouble(1, cutoff)
        }, row: { s in removed.append(Self.parse(s)) })

        var total = count()
        if total > limit {
            try db.run("SELECT * FROM capture_records ORDER BY created_at ASC LIMIT \(total - limit);", row: { s in
                removed.append(Self.parse(s))
            })
        }
        for r in removed { try delete(id: r.id) }
        return removed.count
    }

    public func count() -> Int {
        var n = 0
        try? db.run("SELECT COUNT(*) FROM capture_records;", row: { s in n = Int(s.int(0)) })
        return n
    }

    public func totalBytes() -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        for name in ["captures.sqlite", "captures.sqlite-wal", "captures.sqlite-shm"] {
            let url = root.appendingPathComponent(name)
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int64 {
                total += size
            }
        }
        for dir in ["captures", "capture-thumbnails"] {
            let url = root.appendingPathComponent(dir, isDirectory: true)
            if let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                for f in files {
                    if let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                        total += Int64(size)
                    }
                }
            }
        }
        return total
    }

    public func fileURL(of record: CaptureRecord) -> URL {
        root.appendingPathComponent(record.file)
    }

    public func thumbnailURL(of record: CaptureRecord) -> URL? {
        record.thumbnailFile.map { root.appendingPathComponent($0) }
    }

    // MARK: - Private

    private static func parse(_ s: SQLiteDatabase.Statement) -> CaptureRecord {
        CaptureRecord(
            id: UUID(uuidString: s.text(0) ?? "") ?? UUID(),
            file: s.text(1) ?? "",
            thumbnailFile: s.text(2),
            width: Int(s.int(3)),
            height: Int(s.int(4)),
            byteCount: Int(s.int(5)),
            createdAt: Date(timeIntervalSince1970: s.double(6))
        )
    }

    /// 图片先写临时文件再原子替换，避免崩溃留下半文件。
    static func atomicWrite(data: Data, to url: URL) throws {
        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent(".tmp-\(UUID().uuidString)")
        try data.write(to: tmpURL)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.moveItem(at: tmpURL, to: url)
    }

    /// 缩略图：长边不超过 maxPixel 的 PNG。
    static func thumbnailPNG(from image: CGImage, maxPixel: Int) -> Data {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return Data() }
        var targetW = w
        var targetH = h
        if max(w, h) > maxPixel {
            let scale = Double(maxPixel) / Double(max(w, h))
            targetW = max(1, Int(Double(w) * scale))
            targetH = max(1, Int(Double(h) * scale))
        }
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: targetW, pixelsHigh: targetH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return Data() }
        out.size = NSSize(width: targetW, height: targetH)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: image, size: NSSize(width: w, height: h))
            .draw(in: NSRect(x: 0, y: 0, width: targetW, height: targetH))
        NSGraphicsContext.restoreGraphicsState()
        return out.representation(using: .png, properties: [:]) ?? Data()
    }
}
