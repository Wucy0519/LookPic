import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageResizer {
    static let maxEdge = 16384

    static func pixelSize(of image: NSImage) -> NSSize {
        var best = NSSize.zero
        for rep in image.representations {
            let width = rep.pixelsWide
            let height = rep.pixelsHigh
            if width > 0, height > 0, width * height > Int(best.width * best.height) {
                best = NSSize(width: width, height: height)
            }
        }
        if best.width > 0, best.height > 0 { return best }
        return image.size
    }

    static func resizedImage(_ image: NSImage, width: Int, height: Int, opaque: Bool) -> CGImage? {
        guard width > 0, height > 0, width <= maxEdge, height <= maxEdge else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        if opaque {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    static func outputURL(source: URL, width: Int, height: Int, directory: URL) -> URL {
        let ext = outputExtension(for: source)
        let base = source.deletingPathExtension().lastPathComponent
        var url = directory.appendingPathComponent(base).appendingPathExtension(ext)
        if url.standardizedFileURL.path == source.standardizedFileURL.path {
            url = directory.appendingPathComponent("\(base)_\(width)x\(height)").appendingPathExtension(ext)
        }
        return url
    }

    static func uniqueURL(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let directory = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var index = 2
        var candidate = url
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    static func write(_ image: CGImage, to url: URL) throws {
        let type = uti(for: url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw Failure("无法写入 \(url.lastPathComponent)")
        }
        let properties: [CFString: Any]
        if type == UTType.jpeg.identifier {
            properties = [kCGImageDestinationLossyCompressionQuality: 0.92]
        } else {
            properties = [:]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure("保存失败")
        }
    }

    static func outputExtension(for source: URL) -> String {
        switch source.pathExtension.lowercased() {
        case "jpg", "jpeg": return "jpg"
        case "tif", "tiff": return "tiff"
        case "heic", "heif": return "heic"
        case "png": return "png"
        default: return "png"
        }
    }

    private static func uti(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return UTType.jpeg.identifier
        case "tif", "tiff": return UTType.tiff.identifier
        case "heic", "heif": return UTType.heic.identifier
        default: return UTType.png.identifier
        }
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static func runSelfTest() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        guard let cg = resizedImage(image, width: 4, height: 6, opaque: false) else {
            fputs("self-test failed: resize\n", stderr)
            exit(1)
        }
        expect(cg.width == 4 && cg.height == 6, "输出像素应为 4×6")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-resize-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original").appendingPathComponent("shot.png")
        try! FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = outputURL(source: source, width: 4, height: 6, directory: root)
        expect(destination.lastPathComponent == "shot.png", "不同路径时保留原文件名")
        try! write(cg, to: destination)
        guard let saved = NSImage(contentsOf: destination) else {
            fputs("self-test failed: reload\n", stderr)
            exit(1)
        }
        let size = pixelSize(of: saved)
        expect(Int(size.width) == 4 && Int(size.height) == 6, "读回的分辨率应为 4×6")

        let sameFolder = outputURL(source: destination, width: 8, height: 8, directory: root)
        expect(sameFolder.lastPathComponent == "shot_8x8.png", "覆盖原图时应改名")
        FileManager.default.createFile(atPath: sameFolder.path, contents: Data())
        let unique = uniqueURL(for: sameFolder)
        expect(unique.lastPathComponent == "shot_8x8 2.png", "重名时应追加序号")
    }
}
