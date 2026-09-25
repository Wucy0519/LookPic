import Foundation

struct ImageCatalog {
    let directory: URL
    let files: [URL]

    static let extensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff",
        "heic", "heif", "webp", "avif", "ico", "icns", "jp2"
    ]

    static func load(containing url: URL) -> ImageCatalog {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.filter(isImageFile).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        } ?? []
        return ImageCatalog(directory: directory, files: files)
    }

    func index(of url: URL) -> Int? {
        let target = url.standardizedFileURL.path
        return files.firstIndex { $0.standardizedFileURL.path == target }
    }

    func previous(before index: Int) -> Int? {
        let next = index - 1
        return files.indices.contains(next) ? next : nil
    }

    func next(after index: Int) -> Int? {
        let next = index + 1
        return files.indices.contains(next) ? next : nil
    }

    private static func isImageFile(_ url: URL) -> Bool {
        guard extensions.contains(url.pathExtension.lowercased()) else { return false }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true
    }

    static func runSelfTest() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-catalog-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("photos", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["b.JPG", "a.png", "notes.txt", "img10.heic", "img2.png", ".hidden.png"] {
            FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data())
        }
        try! FileManager.default.createDirectory(at: folder.appendingPathComponent("nested.jpg"), withIntermediateDirectories: true)

        let catalog = ImageCatalog.load(containing: folder.appendingPathComponent("b.JPG"))
        let names = catalog.files.map(\.lastPathComponent)
        expect(names == ["a.png", "b.JPG", "img2.png", "img10.heic"], "排序应为 \(names)")
        expect(catalog.index(of: folder.appendingPathComponent("b.JPG")) == 1, "b.JPG 的序号")
        expect(catalog.previous(before: 0) == nil, "第一张没有上一张")
        expect(catalog.next(after: 3) == nil, "最后一张没有下一张")
        expect(catalog.next(after: 2) == 3, "img2 的下一张应是 img10")
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("self-test failed: \(message)\n", stderr)
        exit(1)
    }
}
