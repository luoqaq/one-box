import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import CaptureStore

/// CaptureStore 测试：插入、列表、删除、清理与文件同步。
struct CaptureStoreTests {

    private func makeStore() throws -> CaptureStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ob-cap-tests-\(UUID().uuidString)", isDirectory: true)
        return try CaptureStore(directory: dir)
    }

    private func makePNG(width: Int = 10, height: Int = 6) throws -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
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

    @Test("插入落盘并可列出")
    func insertAndList() async throws {
        let store = try makeStore()
        let record = try await store.insert(png: try makePNG())

        #expect(record.width == 10)
        #expect(record.height == 6)
        #expect(record.byteCount > 0)

        let list = await store.records()
        #expect(list.count == 1)
        #expect(list.first?.id == record.id)

        let url = await store.fileURL(of: record)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("列表按时间倒序")
    func listOrder() async throws {
        let store = try makeStore()
        let a = try await store.insert(png: try makePNG())
        try await Task.sleep(nanoseconds: 50_000_000)
        let b = try await store.insert(png: try makePNG())
        let list = await store.records()
        #expect(list.map(\.id) == [b.id, a.id])
    }

    @Test("删除记录同步删除文件")
    func delete() async throws {
        let store = try makeStore()
        let record = try await store.insert(png: try makePNG())
        let url = await store.fileURL(of: record)
        try await store.delete(id: record.id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let count = await store.count()
        #expect(count == 0)
    }

    @Test("清理保留上限数量")
    func retention() async throws {
        let store = try makeStore()
        for _ in 0..<5 {
            _ = try await store.insert(png: try makePNG())
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let removed = try await store.enforceRetention(limit: 2, days: 3650)
        #expect(removed == 3)
        let count = await store.count()
        #expect(count == 2)
    }
}
