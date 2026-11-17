import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 剪贴板元数据存储 + 图片/缩略图文件管理。
/// 数据库与文件都在 ~/Library/Application Support/OneBox/ 下：
/// store.sqlite、images/<uuid>.png、thumbnails/<uuid>.png。
public actor ClipboardStore {
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("OneBox", isDirectory: true)
    }

    private let root: URL
    private let db: SQLiteDatabase

    public init(directory: URL? = nil) throws {
        let root = directory ?? Self.defaultDirectory()
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("images", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("thumbnails", isDirectory: true), withIntermediateDirectories: true)
        self.db = try SQLiteDatabase(path: root.appendingPathComponent("store.sqlite").path)
        try db.execute("""
        CREATE TABLE IF NOT EXISTS clipboard_records(
            id TEXT PRIMARY KEY,
            kind INTEGER NOT NULL,
            text_content TEXT,
            content_hash TEXT NOT NULL UNIQUE,
            image_file TEXT,
            thumbnail_file TEXT,
            image_width INTEGER,
            image_height INTEGER,
            byte_count INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            last_used_at REAL NOT NULL,
            use_count INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_clip_hash ON clipboard_records(content_hash);
        CREATE INDEX IF NOT EXISTS idx_clip_used ON clipboard_records(last_used_at DESC);
        """)
    }

    // MARK: - 写入

    /// 插入文本记录。
    @discardableResult
    public func insert(text: String, hash: String) throws -> ClipboardRecord {
        let record = ClipboardRecord(
            kind: .text,
            textContent: text,
            contentHash: hash,
            byteCount: text.utf8.count
        )
        try insert(record)
        return record
    }

    /// 插入图片记录：写 PNG + 缩略图（原子替换），再入库。
    @discardableResult
    public func insertImage(png: Data, hash: String) throws -> ClipboardRecord {
        let (imageRel, thumbRel, w, h) = try Self.writeImageFiles(png: png, root: root)
        let record = ClipboardRecord(
            kind: .image,
            contentHash: hash,
            imageFile: imageRel,
            thumbnailFile: thumbRel,
            imageWidth: w,
            imageHeight: h,
            byteCount: png.count
        )
        try insert(record)
        return record
    }

    private func insert(_ record: ClipboardRecord) throws {
        try db.run("""
        INSERT OR IGNORE INTO clipboard_records
        (id, kind, text_content, content_hash, image_file, thumbnail_file, image_width, image_height,
         byte_count, created_at, last_used_at, use_count, pinned)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?);
        """, bind: { s in
            s.bindText(1, record.id.uuidString)
            s.bindInt(2, Int64(record.kind.rawValue))
            s.bindText(3, record.textContent)
            s.bindText(4, record.contentHash)
            s.bindText(5, record.imageFile)
            s.bindText(6, record.thumbnailFile)
            s.bindInt(7, record.imageWidth.map(Int64.init))
            s.bindInt(8, record.imageHeight.map(Int64.init))
            s.bindInt(9, Int64(record.byteCount))
            s.bindDouble(10, record.createdAt.timeIntervalSince1970)
            s.bindDouble(11, record.lastUsedAt.timeIntervalSince1970)
            s.bindInt(12, Int64(record.useCount))
            s.bindInt(13, record.pinned ? 1 : 0)
        })
    }

    /// 重复内容：更新使用时间与次数，不生成新条目。
    public func updateUsed(id: UUID) throws {
        try db.run("""
        UPDATE clipboard_records
        SET last_used_at = ?, use_count = use_count + 1
        WHERE id = ?;
        """, bind: { s in
            s.bindDouble(1, Date().timeIntervalSince1970)
            s.bindText(2, id.uuidString)
        })
    }

    public func setPinned(id: UUID, _ pinned: Bool) throws {
        try db.run("UPDATE clipboard_records SET pinned = ? WHERE id = ?;", bind: { s in
            s.bindInt(1, pinned ? 1 : 0)
            s.bindText(2, id.uuidString)
        })
    }

    /// 删除单条记录，同时删除图片与缩略图文件。
    public func delete(id: UUID) throws {
        if let record = record(id: id) {
            removeFile(record.imageFile)
            removeFile(record.thumbnailFile)
        }
        try db.run("DELETE FROM clipboard_records WHERE id = ?;", bind: { s in
            s.bindText(1, id.uuidString)
        })
    }

    /// 清空历史：数据库记录和资源文件一并删除。
    public func clear() throws {
        var files: [(String?)] = []
        try db.run("SELECT image_file, thumbnail_file FROM clipboard_records;", row: { s in
            files.append((s.text(0)))
            files.append((s.text(1)))
        })
        try db.run("DELETE FROM clipboard_records;")
        for f in files { removeFile(f) }
    }

    // MARK: - 查询

    public func record(id: UUID) -> ClipboardRecord? {
        var result: ClipboardRecord?
        try? db.run("SELECT * FROM clipboard_records WHERE id = ? LIMIT 1;", bind: { s in
            s.bindText(1, id.uuidString)
        }, row: { s in
            if result == nil { result = Self.record(from: s) }
        })
        return result
    }

    /// 去重查询。
    public func record(contentHash: String) -> ClipboardRecord? {
        var result: ClipboardRecord?
        try? db.run("SELECT * FROM clipboard_records WHERE content_hash = ? LIMIT 1;", bind: { s in
            s.bindText(1, contentHash)
        }, row: { s in
            if result == nil { result = Self.record(from: s) }
        })
        return result
    }

    public func records(
        filter: ClipboardRecordFilter = .all,
        search: String = "",
        limit: Int = 200
    ) -> [ClipboardRecord] {
        var sql = "SELECT * FROM clipboard_records"
        var conditions: [String] = []
        switch filter {
        case .all: break
        case .text: conditions.append("kind = \(ClipboardRecord.Kind.text.rawValue)")
        case .image: conditions.append("kind = \(ClipboardRecord.Kind.image.rawValue)")
        case .pinned: conditions.append("pinned = 1")
        }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let escaped = q.replacingOccurrences(of: "'", with: "''")
            conditions.append("text_content LIKE '%\(escaped)%'")
        }
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        sql += " ORDER BY pinned DESC, last_used_at DESC LIMIT \(max(1, limit));"
        var results: [ClipboardRecord] = []
        try? db.run(sql, row: { s in
            results.append(Self.record(from: s))
        })
        return results
    }

    public func count() -> Int {
        var n = 0
        try? db.run("SELECT COUNT(*) FROM clipboard_records;", row: { s in
            n = Int(s.int(0))
        })
        return n
    }

    /// 本模块磁盘占用（数据库 + 图片 + 缩略图）。
    public func totalBytes() -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        for name in ["store.sqlite", "store.sqlite-wal", "store.sqlite-shm"] {
            let url = root.appendingPathComponent(name)
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int64 {
                total += size
            }
        }
        for dir in ["images", "thumbnails"] {
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

    // MARK: - 清理策略

    /// 超数量/超天数清理未置顶条目；置顶条目不参与清理。返回删除的条数。
    @discardableResult
    public func enforceRetention(limit: Int, days: Int) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        // 1) 过期：未置顶且 lastUsedAt 超过天数。
        var expired: [ClipboardRecord] = []
        try db.run("SELECT * FROM clipboard_records WHERE pinned = 0 AND last_used_at < ?;", bind: { s in
            s.bindDouble(1, cutoff)
        }, row: { s in
            expired.append(Self.record(from: s))
        })
        for r in expired { try delete(id: r.id) }

        // 2) 超量：未置顶按 lastUsedAt 最旧开始删。
        var excess: [ClipboardRecord] = []
        let remaining = count()
        if remaining > limit {
            let overflow = remaining - limit
            try db.run("""
            SELECT * FROM clipboard_records WHERE pinned = 0
            ORDER BY last_used_at ASC LIMIT \(overflow);
            """, row: { s in
                excess.append(Self.record(from: s))
            })
            for r in excess { try delete(id: r.id) }
        }
        return expired.count + excess.count
    }

    // MARK: - 文件访问

    public func imageURL(of record: ClipboardRecord) -> URL? {
        record.imageFile.map { root.appendingPathComponent($0) }
    }

    public func thumbnailURL(of record: ClipboardRecord) -> URL? {
        record.thumbnailFile.map { root.appendingPathComponent($0) }
    }

    // MARK: - Private

    private func removeFile(_ relative: String?) {
        guard let relative else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(relative))
    }

    private static func record(from s: SQLiteDatabase.Statement) -> ClipboardRecord {
        ClipboardRecord(
            id: UUID(uuidString: s.text(0) ?? UUID().uuidString) ?? UUID(),
            kind: ClipboardRecord.Kind(rawValue: Int(s.int(1))) ?? .text,
            textContent: s.text(2),
            contentHash: s.text(3) ?? "",
            imageFile: s.text(4),
            thumbnailFile: s.text(5),
            imageWidth: s.int(6) != 0 ? Int(s.int(6)) : nil,
            imageHeight: s.int(7) != 0 ? Int(s.int(7)) : nil,
            byteCount: Int(s.int(8)),
            createdAt: Date(timeIntervalSince1970: s.double(9)),
            lastUsedAt: Date(timeIntervalSince1970: s.double(10)),
            useCount: Int(s.int(11)),
            pinned: s.int(12) == 1
        )
    }

    /// 图片先写临时文件再原子替换，避免崩溃留下半文件。
    /// 返回 (imageRel, thumbRel, width, height)。
    static func writeImageFiles(png: Data, root: URL) throws -> (String, String, Int?, Int?) {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "OneBox.ClipboardStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法解码 PNG 数据"])
        }
        let uuid = UUID().uuidString
        let imageRel = "images/\(uuid).png"
        let thumbRel = "thumbnails/\(uuid).png"
        let imageURL = root.appendingPathComponent(imageRel)
        let thumbURL = root.appendingPathComponent(thumbRel)

        try atomicWrite(data: png, to: imageURL)
        let thumbData = Self.thumbnailPNG(from: image, maxPixel: 320)
        try atomicWrite(data: thumbData, to: thumbURL)
        return (imageRel, thumbRel, image.width, image.height)
    }

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

    /// 缩略图：短边不超过 maxPixel 的 PNG。
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
        let out = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: targetW, pixelsHigh: targetH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
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
