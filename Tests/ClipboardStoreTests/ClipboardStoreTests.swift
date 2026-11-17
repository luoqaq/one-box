import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import ClipboardStore

/// ClipboardStore 测试：文本/图片插入、去重、删除、清理策略与文件同步。
struct ClipboardStoreTests {

    private func makeStore() throws -> ClipboardStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ob-clip-tests-\(UUID().uuidString)", isDirectory: true)
        return try ClipboardStore(directory: dir)
    }

    /// 生成纯色 PNG 测试数据。
    private func makePNG(r: UInt8, g: UInt8, b: UInt8, width: Int = 8, height: Int = 8) throws -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "test", code: 1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    @Test("文本插入与 hash 去重：第二次只更新使用时间")
    func textInsertAndDedup() async throws {
        let store = try makeStore()
        let r1 = try await store.insert(text: "hello onebox", hash: "h1")
        try await store.updateUsed(id: r1.id)
        try await store.updateUsed(id: r1.id)

        let found = await store.record(contentHash: "h1")
        #expect(found?.id == r1.id)
        let count = await store.count()
        #expect(count == 1)

        _ = try await store.insert(text: "second", hash: "h2")
        let count2 = await store.count()
        #expect(count2 == 2)
    }

    @Test("图片插入生成文件与缩略图，删除时同步清理")
    func imageLifecycle() async throws {
        let store = try makeStore()
        let png = try makePNG(r: 255, g: 0, b: 0)
        let record = try await store.insertImage(png: png, hash: "img1")

        #expect(record.kind == .image)
        #expect(record.imageWidth == 8)
        #expect(record.imageHeight == 8)
        #expect(record.byteCount == png.count)

        let imageURL = await store.imageURL(of: record)
        #expect(imageURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        let thumbURL = await store.thumbnailURL(of: record)
        #expect(thumbURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)

        try await store.delete(id: record.id)
        #expect(imageURL.map { FileManager.default.fileExists(atPath: $0.path) } == false)
        #expect(thumbURL.map { FileManager.default.fileExists(atPath: $0.path) } == false)
        let count = await store.count()
        #expect(count == 0)
    }

    @Test("清空历史删除全部记录与文件")
    func clear() async throws {
        let store = try makeStore()
        _ = try await store.insert(text: "a", hash: "a")
        _ = try await store.insertImage(png: try makePNG(r: 0, g: 255, b: 0), hash: "b")
        try await store.clear()
        let count = await store.count()
        #expect(count == 0)
    }

    @Test("记录过滤与搜索")
    func recordsFilterSearch() async throws {
        let store = try makeStore()
        _ = try await store.insert(text: "OneBox V1 验收清单", hash: "t1")
        _ = try await store.insert(text: "swift package init", hash: "t2")
        _ = try await store.insertImage(png: try makePNG(r: 0, g: 0, b: 255), hash: "t3")

        let all = await store.records(filter: .all, search: "")
        #expect(all.count == 3)
        let texts = await store.records(filter: .text, search: "")
        #expect(texts.count == 2)
        let images = await store.records(filter: .image, search: "")
        #expect(images.count == 1)
        let hit = await store.records(filter: .all, search: "验收")
        #expect(hit.count == 1)
        #expect(hit.first?.textContent == "OneBox V1 验收清单")
    }

    @Test("置顶条目不参与超量清理")
    func retentionKeepsPinned() async throws {
        let store = try makeStore()
        // 共 6 条（1 条置顶），上限 3 → 删除最旧 3 条未置顶。
        for i in 0..<6 {
            let r = try await store.insert(text: "row-\(i)", hash: "r\(i)")
            if i == 2 {
                try await store.setPinned(id: r.id, true)
            }
        }
        let removed = try await store.enforceRetention(limit: 3, days: 3650)
        #expect(removed == 3)
        let remaining = await store.records(filter: .all, search: "")
        #expect(remaining.count == 3) // 2 未置顶 + 1 置顶
        #expect(remaining.contains { $0.pinned })
    }

    @Test("超天数清理过期记录")
    func retentionByDays() async throws {
        let store = try makeStore()
        _ = try await store.insert(text: "old", hash: "old")
        // days=0 表示 cutoff=now，全部未置顶记录都过期。
        _ = try await store.enforceRetention(limit: 100, days: 0)
        let count = await store.count()
        #expect(count == 0)
    }
}
